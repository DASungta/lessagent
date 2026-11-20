import { client, T3Client } from '../services/T3Client';
import { ActionCard, ApprovalChoice, Question, answerSelected, inputAnswers } from '../protocol/Core';
import { AttachmentPicker } from '../services/AttachmentPicker';
import { DraftAttachment } from '../protocol/R4';
import { common } from '@kit.AbilityKit';
import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';
import { AppButton } from './ui/AppButton';

@Component
export struct RequestCard {
  connection: T3Client = client;
  @StorageLink('t3Foreground') @Watch('clearPrivateInput') foreground: boolean = true;
  private clearPrivateInput(): void {
    if (!this.foreground) { this.secretValue = ''; this.answers = new Map(); this.customAnswers = new Map(); }
  }
  @Prop card: ActionCard;
  @State secretValue: string = '';
  @State answers: Map<string, Object> = new Map();
  @State customAnswers: Map<string, string> = new Map();
  @State busy: boolean = false;
  @State status: string = '';
  @State submitted: boolean = false;
  @State referenceMode: boolean = false;
  @State referenceProvider: string = '';
  @State referencePath: string = '';
  @State attachments: Map<string, DraftAttachment[]> = new Map();
  @State uploadBusy: string = '';
  private picker: AttachmentPicker | undefined = undefined;

  aboutToDisappear(): void {
    this.secretValue = ''; this.answers = new Map(); this.customAnswers = new Map();
  }
  aboutToAppear(): void {
    for (const q of this.card.questions) {
      if (q.initial && !this.customAnswers.has(q.id)) this.customAnswers.set(q.id, q.initial);
    }
  }

  private choose(q: Question, value: string): void {
    if (this.customAnswers.has(q.id)) {
      this.customAnswers.delete(q.id);
      this.customAnswers = new Map(this.customAnswers);
    }
    if (q.multi) {
      const values = (this.answers.get(q.id) || []) as string[];
      this.answers.set(q.id, values.includes(value) ? values.filter((v: string) => v !== value) : values.concat(value));
    } else this.answers.set(q.id, value);
    this.answers = new Map(this.answers);
  }

  private selected(q: Question, value: string): boolean {
    const custom = this.customAnswers.get(q.id);
    return (!custom || !custom.trim()) && answerSelected(this.answers.get(q.id), value);
  }

  private customText(q: Question): string {
    const custom = this.customAnswers.get(q.id);
    if (custom !== undefined) return custom;
    return typeof this.answers.get(q.id) === 'string' ? this.answers.get(q.id) as string : q.initial;
  }

  private finalAnswers(): Record<string, Object> {
    const result: Record<string, Object> = {};
    for (const q of this.card.questions) {
      const custom = this.customAnswers.get(q.id);
      if (custom !== undefined && custom.trim()) result[q.id] = custom;
      else if (this.answers.has(q.id)) result[q.id] = this.answers.get(q.id) as Object;
    }
    return result;
  }

  private async submit(decision: string): Promise<void> {
    if (this.busy || this.submitted) return;
    this.busy = true;
    const value = this.secretValue;
    const answers = this.card.kind === 'input' ? this.finalAnswers() : inputAnswers(this.answers);
    this.secretValue = '';
    try {
      if (this.card.kind === 'secret') {
        if (this.referenceMode) await this.connection.secretReference(this.card.id, this.referenceProvider, this.referencePath);
        else await this.connection.secret(this.card.id, value, decision === 'decline');
        this.submitted = true;
      }
      else {
        if (this.card.kind === 'input') {
          for (const q of this.card.questions) {
            const answer = answers[q.id];
            if (q.required && (answer === undefined || (typeof answer === 'string' && !answer.trim()) || (Array.isArray(answer) && (answer.length === 0 || answer.every((value: Object) => typeof value === 'string' && !value.trim()))))) throw new Error('请回答所有必填问题');
          }
        }
        const attachmentAnswers: Record<string, Object[]> = {};
        for (const q of this.card.questions) {
          const map = this.attachments;
          const rows = map && map.get ? (map.get(q.id) || []) : [];
          if (rows.length) attachmentAnswers[q.id] = rows.slice();
        }
        await this.connection.respond(this.card.requestId, decision, answers, attachmentAnswers);
        this.answers = new Map();
        this.customAnswers = new Map();
        this.submitted = true;
      }
      this.status = '已提交，等待服务端更新';
    } catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; }
  }

  private async addQuestionAttachment(q: Question): Promise<void> {
    if (this.uploadBusy || this.busy) return;
    if (!this.picker) this.picker = new AttachmentPicker(this.connection);
    this.uploadBusy = q.id;
    try {
      const before = this.connection.attachments.slice();
      await this.picker.choose();
      const added = this.connection.attachments.filter((item: DraftAttachment) =>
        !before.some((old: DraftAttachment) => old.id === item.id));
      if (added.length) this.attachments.set(q.id, this.questionAttachments(q.id).concat(added));
      this.attachments = new Map(this.attachments);
      this.connection.attachments = before; this.connection.attachment = before[0];
    } catch (error) { this.status = '问题附件上传失败：' + (error as Error).message; }
    finally { this.uploadBusy = ''; }
  }

  private removeQuestionAttachment(questionId: string, id: string): void {
    this.attachments.set(questionId, this.questionAttachments(questionId).filter((item: DraftAttachment) => item.id !== id));
    this.attachments = new Map(this.attachments);
  }
  private questionAttachments(questionId: string): DraftAttachment[] {
    if (!this.attachments) return [];
    const rows = this.attachments.get(questionId);
    return rows === undefined ? [] : rows;
  }

  private async dismiss(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try { await this.connection.dismissInput(this.card.requestId); this.submitted = true; this.status = '问题已关闭'; }
    catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; }
  }

  private async openSecretUrl(): Promise<void> {
    if (!/^https?:\/\/[^/]+/i.test(this.card.secretUrl) || /\s/.test(this.card.secretUrl)) {
      this.status = '请求页面地址无效';
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.startAbility({ action: 'ohos.want.action.viewData', uri: this.card.secretUrl,
        entities: ['entity.system.browsable'] });
    } catch (_) { this.status = '无法打开请求页面：' + this.card.secretUrl; }
  }
  private secretProviders(): string[] {
    const settings = this.connection.serverSettings;
    if (!settings || settings.secretProviders === undefined || settings.secretProviders === null) return [];
    const row = settings.secretProviders as Record<string, Object>;
    return Object.keys(row);
  }

  build() {
    Column({ space: Space.sm }) {
      Text(this.card.kind === 'secret' ? '安全输入' : this.card.kind === 'approval' ? '需要审批' : '需要你的回答')
        .fontSize(FontSize.callout)
        .fontWeight(Weight.semibold)
        .fontColor(this.card.kind === 'approval' ? $r('app.color.warning') : $r('app.color.muted'))
        .width('100%')
      Text(this.card.label)
        .fontSize(FontSize.body)
        .lineHeight(LineHeight.body)
        .fontColor($r('app.color.ink'))
        .fontWeight(Weight.medium)
        .width('100%')
      if (this.card.kind === 'secret') {
        if (!this.card.enabled) {
          Text('等待在原会话中回答').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
        } else {
          Text('敏感值仅发往专用接口，不进入聊天、草稿或剪贴板。').fontSize(FontSize.caption).lineHeight(LineHeight.caption)
            .fontColor($r('app.color.muted')).width('100%')
          if (this.card.detail && this.card.detail !== this.card.label) {
            Text(this.card.detail).fontSize(FontSize.callout).lineHeight(LineHeight.callout).width('100%')
          }
          if (this.card.secretDelivery === 'file') {
            Text('该值只会写入仅所有者可读的文件，供 Agent 命令使用。').fontSize(FontSize.caption).lineHeight(LineHeight.caption)
              .fontColor($r('app.color.muted')).width('100%')
          }
          if (this.card.secretUrl) {
            AppButton({ label: '打开请求页面', kind: 'text', compact: true, onTap: () => { void this.openSecretUrl(); } })
          }
          if (this.card.secretReference && this.connection.config.secretRequestReferences === true) {
            Row({ space: Space.xs }) {
              AppButton({ label: this.referenceMode ? '使用引用' : '直接输入', kind: 'text', compact: true,
                onTap: () => { this.referenceMode = !this.referenceMode; } })
            }.width('100%')
          }
          if (this.referenceMode) {
            if (this.secretProviders().length) {
              Text('来源').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.secretProviders(), (name: string) => {
                  Button(name).constraintSize({ minHeight: 38 }).fontSize(FontSize.callout)
                    .fontWeight(this.referenceProvider === name ? Weight.semibold : Weight.medium)
                    .borderRadius(Radius.button).margin({ right: Space.xs, bottom: Space.xs })
                    .backgroundColor(this.referenceProvider === name ? $r('app.color.info_bg') : $r('app.color.group'))
                    .fontColor(this.referenceProvider === name ? $r('app.color.primary_text') : $r('app.color.ink'))
                    .border({ width: 1, color: this.referenceProvider === name ? $r('app.color.primary') : Color.Transparent })
                    .onClick(() => this.referenceProvider = name)
                })
              }.width('100%')
            } else {
              Text('服务端没有可用的秘密来源，请直接输入或先配置来源。').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
            }
            TextInput({ placeholder: '引用路径（不会发送秘密值本身）', text: this.referencePath })
              .enableAutoFill(false).fontSize(FontSize.body).constraintSize({ minHeight: 44 })
              .backgroundColor($r('app.color.input_bg')).border({ width: 1, color: $r('app.color.input_border') })
              .borderRadius(Radius.button).onChange((value: string) => this.referencePath = value)
            AppButton({ label: '使用引用提交', kind: 'primary', compact: true, fill: true,
              disabled: this.busy || this.submitted || !this.referenceProvider.trim() || !this.referencePath.trim(),
              onTap: () => { void this.submit(''); } })
          } else {
            TextInput({ placeholder: this.card.secretPlaceholder || '敏感输入', text: this.secretValue }).type(InputType.Password).enableAutoFill(false)
              .fontSize(FontSize.body).constraintSize({ minHeight: 44 })
              .backgroundColor($r('app.color.input_bg')).border({ width: 1, color: $r('app.color.input_border') })
              .borderRadius(Radius.button).onChange((value: string) => this.secretValue = value)
            AppButton({ label: '安全提交', kind: 'primary', compact: true, fill: true,
              disabled: this.busy || this.submitted || this.secretValue.trim().length === 0,
              onTap: () => { void this.submit(''); } })
          }
          AppButton({ label: '拒绝提供', kind: 'secondary', compact: true, fill: true,
            disabled: this.busy || this.submitted,
            onTap: () => { void this.submit('decline'); } })
        }
      } else if (this.card.kind === 'approval') {
        if (this.card.detail && this.card.detail !== this.card.label) {
          Text(this.card.detail).fontSize(FontSize.mono).lineHeight(LineHeight.mono).fontFamily('monospace')
            .fontColor($r('app.color.ink')).width('100%')
        }
        if (this.card.approvalOptions.length) {
          ForEach(this.card.approvalOptions, (option: ApprovalChoice) => {
            AppButton({
              label: option.label + (option.warning ? ' · ' + option.warning : ''),
              kind: option.decision === 'accept' ? 'confirm' : 'secondary',
              compact: true, fill: true,
              disabled: !this.card.enabled || this.card.responseType !== 'live' || this.busy || this.submitted,
              onTap: () => { void this.submit(option.decision); }
            })
          })
        } else {
          Row({ space: Space.xs }) {
            Column() {
              AppButton({ label: '拒绝本次', kind: 'secondary', compact: true, fill: true,
                disabled: !this.card.enabled || this.card.responseType !== 'live' || this.busy || this.submitted,
                onTap: () => { void this.submit('decline'); } })
            }.layoutWeight(1)
            Column() {
              AppButton({ label: '允许本次', kind: 'confirm', compact: true, fill: true,
                disabled: !this.card.enabled || this.card.responseType !== 'live' || this.busy || this.submitted,
                onTap: () => { void this.submit('accept'); } })
            }.layoutWeight(1)
          }.width('100%')
          AppButton({ label: '允许本会话', kind: 'text', fill: true,
            disabled: !this.card.enabled || this.card.responseType !== 'live' || this.busy || this.submitted,
            onTap: () => { void this.submit('acceptForSession'); } })
        }
      } else {
        ForEach(this.card.questions, (q: Question) => {
          Text(q.label + (q.required ? '（必填）' : '（可选）')).fontSize(FontSize.body).fontWeight(Weight.medium).width('100%')
          ForEach(q.options, (option: string, index: number) => {
            Button((this.selected(q, q.values[index]) ? '✓ ' : '') + option)
              .width('100%').fontSize(FontSize.callout).constraintSize({ minHeight: 40 }).borderRadius(Radius.button)
              .fontWeight(this.selected(q, q.values[index]) ? Weight.semibold : Weight.medium)
              .backgroundColor(this.selected(q, q.values[index]) ? $r('app.color.info_bg') : $r('app.color.group'))
              .fontColor(this.selected(q, q.values[index]) ? $r('app.color.primary_text') : $r('app.color.ink'))
              .border({ width: 1, color: this.selected(q, q.values[index]) ? $r('app.color.primary') : Color.Transparent })
              .accessibilityText(option + (this.selected(q, q.values[index]) ? '，已选中' : '，未选中'))
              .onClick(() => this.choose(q, q.values[index])).enabled(!this.busy && !this.submitted)
          })
          if (q.custom) {
            TextInput({ placeholder: '回答（仅本次提交）', text: this.customText(q) })
              .enableAutoFill(false).fontSize(FontSize.body).constraintSize({ minHeight: 44 })
              .backgroundColor($r('app.color.input_bg')).border({ width: 1, color: $r('app.color.input_border') })
              .borderRadius(Radius.button).enabled(!this.busy && !this.submitted).onChange((value: string) => {
                this.customAnswers.set(q.id, value); this.customAnswers = new Map(this.customAnswers);
              })
          }
          AppButton({ label: this.uploadBusy === q.id ? '上传中…' : '添加问题附件', kind: 'text', compact: true,
            disabled: this.busy || this.submitted || this.uploadBusy === q.id,
            onTap: () => { void this.addQuestionAttachment(q); } })
          ForEach(this.questionAttachments(q.id), (item: DraftAttachment) => {
            Text('附件 · ' + item.name + ' ×').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .constraintSize({ minHeight: 40 }).accessibilityText('移除附件：' + item.name)
              .onClick(() => this.removeQuestionAttachment(q.id, item.id))
          }, (item: DraftAttachment) => q.id + ':' + item.id)
          Text(this.answers.get(q.id) || (this.customAnswers.get(q.id) || '').trim() ? '已填写/选择' : '待回答')
            .fontSize(FontSize.caption).fontColor($r('app.color.muted'))
        })
        AppButton({ label: '提交回答', kind: 'primary', compact: true, fill: true,
          disabled: !this.card.enabled || this.busy || this.submitted,
          onTap: () => { void this.submit(''); } })
        if (this.card.canDismiss) {
          AppButton({ label: '关闭问题', kind: 'secondary', compact: true, fill: true,
            disabled: this.busy || this.submitted,
            onTap: () => { void this.dismiss(); } })
        }
      }
      if (!this.card.enabled) {
        Text('此请求不可恢复，请停止后重新发起任务').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
      }
      if (this.status) {
        Text(this.status).fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
      }
    }.padding(Space.md).width('100%').alignItems(HorizontalAlign.Start)
      .backgroundColor(this.card.kind === 'approval' ? $r('app.color.warning_bg') : $r('app.color.card'))
      .foregroundColor($r('app.color.ink')).borderRadius(Radius.card)
      .border({ width: 1, color: this.card.kind === 'approval' ? $r('app.color.warning_border') : $r('app.color.border') })
  }
}
