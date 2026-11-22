import { client, T3Client } from '../services/T3Client';
import {
  ActionCard,
  ApprovalChoice,
  Question,
  QuestionDisplay,
  QuestionOption,
  SecretField,
  answerSelected,
  inputAnswers,
  questionDisplays,
  secretRequestErrorMessage,
  secretValuesFromMap
} from '../protocol/Core';
import { AttachmentPicker } from '../services/AttachmentPicker';
import { DraftAttachment } from '../protocol/R4';
import { common } from '@kit.AbilityKit';
import { FontSize, LineHeight, Opacity, Radius, Sizes, Space, Weight } from '../common/Theme';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';

@Component
export struct RequestCard {
  connection: T3Client = client;
  @StorageLink('t3Foreground') @Watch('clearPrivateInput') foreground: boolean = true;
  private clearPrivateInput(): void {
    if (!this.foreground) {
      this.secretValue = '';
      this.secretValues = new Map();
      this.secretVisible = false;
      this.fieldVisible = new Map();
      this.answers = new Map();
      this.customAnswers = new Map();
    }
  }
  @Prop card: ActionCard;
  @State secretValue: string = '';
  @State secretValues: Map<string, string> = new Map();
  @State secretVisible: boolean = false;
  @State fieldVisible: Map<string, boolean> = new Map();
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
    this.secretValue = '';
    this.secretValues = new Map();
    this.secretVisible = false;
    this.fieldVisible = new Map();
    this.answers = new Map();
    this.customAnswers = new Map();
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
    return custom !== undefined ? custom : '';
  }

  private hasCustomText(q: Question): boolean {
    const custom = this.customAnswers.get(q.id);
    return custom !== undefined && custom.trim().length > 0;
  }

  private hasSelectedOption(q: Question): boolean {
    const answer = this.answers.get(q.id);
    if (typeof answer === 'string') return answer.trim().length > 0;
    if (Array.isArray(answer)) return answer.some((value: Object) => typeof value === 'string' && value.trim().length > 0);
    return false;
  }

  private questionAnswered(q: Question): boolean {
    return this.hasCustomText(q) || this.hasSelectedOption(q) || (q.custom && this.questionAttachments(q.id).length > 0);
  }

  private requiredProgress(): number[] {
    let total = 0;
    let answered = 0;
    for (const q of this.card.questions) {
      if (q.required) {
        total++;
        if (this.questionAnswered(q)) answered++;
      }
    }
    return [answered, total];
  }

  private allRequiredAnswered(): boolean {
    const counts = this.requiredProgress();
    return counts[0] >= counts[1];
  }

  private progressBadgeText(displays: QuestionDisplay[]): string {
    const counts = this.requiredProgress();
    if (counts[1] > 0) {
      return counts[0] >= counts[1] ? '已全部回答' : counts[0] + '/' + counts[1] + ' 已答';
    }
    const primaryCount = displays.filter((item: QuestionDisplay) => !item.companion).length;
    return primaryCount > 0 ? '共 ' + primaryCount + ' 项' : '';
  }

  private statusColorOf(): ResourceColor {
    if (this.submitted) return $r('app.color.success');
    return $r('app.color.danger');
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

  private hasSecretFields(): boolean {
    return this.card.secretFields !== undefined && this.card.secretFields.length > 0;
  }

  private secretFieldText(name: string): string {
    if (!this.secretValues) return '';
    const value = this.secretValues.get(name);
    return value !== undefined ? value : '';
  }

  private setSecretFieldText(name: string, value: string): void {
    const next = this.secretValues ? new Map(this.secretValues) : new Map<string, string>();
    next.set(name, value);
    this.secretValues = next;
  }

  private isFieldVisible(name: string): boolean {
    if (!this.fieldVisible) return false;
    return this.fieldVisible.get(name) === true;
  }

  private setFieldVisible(name: string, visible: boolean): void {
    const next = this.fieldVisible ? new Map(this.fieldVisible) : new Map<string, boolean>();
    next.set(name, visible);
    this.fieldVisible = next;
  }

  private allSecretFieldsFilled(): boolean {
    if (!this.hasSecretFields()) return this.secretValue.trim().length > 0;
    for (const field of this.card.secretFields) {
      if (this.secretFieldText(field.name).trim().length === 0) return false;
    }
    return true;
  }

  private finalSecretValues(): Record<string, string> {
    if (!this.hasSecretFields()) return {};
    const map = this.secretValues ? this.secretValues : new Map<string, string>();
    return secretValuesFromMap(this.card.secretFields, map);
  }

  private secretDeliveryNote(): string {
    if (this.card.secretFields !== undefined && this.card.secretFields.length > 1) {
      return '这些值只会保存在私密文件中，仅所有者可读，供智能体命令在 24 小时内使用。';
    }
    return '该值只会保存在一个私密文件中，仅所有者可读，供智能体命令在 24 小时内使用。';
  }

  private async submit(decision: string): Promise<void> {
    if (this.busy || this.submitted) return;
    this.busy = true;
    const value = this.secretValue;
    const hasFields = this.hasSecretFields();
    const multiValues = this.finalSecretValues();
    const answers = this.card.kind === 'input' ? this.finalAnswers() : inputAnswers(this.answers);
    this.secretValue = '';
    this.secretValues = new Map();
    this.secretVisible = false;
    this.fieldVisible = new Map();
    try {
      if (this.card.kind === 'secret') {
        if (decision === 'decline') await this.connection.secret(this.card.id, '', true);
        else if (this.referenceMode && !hasFields) await this.connection.secretReference(this.card.id, this.referenceProvider, this.referencePath);
        else if (hasFields) await this.connection.secretValues(this.card.id, multiValues);
        else await this.connection.secret(this.card.id, value, false);
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
    } catch (error) {
      this.status = this.card.kind === 'secret' ? secretRequestErrorMessage(error as Object) : (error as Error).message;
    }
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
      if (this.card.kind === 'input') {
        Row({ space: Space.xs }) {
          Text('需要你的回答')
            .fontSize(FontSize.callout)
            .lineHeight(LineHeight.callout)
            .fontWeight(Weight.semibold)
            .fontColor($r('app.color.muted'))
            .layoutWeight(1)
          if (this.progressBadgeText(questionDisplays(this.card.questions)).length > 0) {
            StatusBadge({
              text: this.progressBadgeText(questionDisplays(this.card.questions)),
              tone: this.requiredProgress()[1] > 0
                ? (this.allRequiredAnswered() ? 'success' : 'info')
                : 'neutral'
            })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (this.card.label && this.card.label !== '需要你的回答') {
          Text(this.card.label)
            .fontSize(FontSize.callout)
            .lineHeight(LineHeight.callout)
            .fontColor($r('app.color.muted'))
            .width('100%')
        }
        Divider().color($r('app.color.separator')).strokeWidth(Sizes.hairline)
      } else {
        Text(this.card.kind === 'secret' ? '安全输入' : '需要审批')
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
      }
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
            Text(this.secretDeliveryNote()).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
              .fontColor($r('app.color.muted')).width('100%')
          }
          if (this.card.secretUrl) {
            AppButton({ label: '打开请求页面', kind: 'text', compact: true, onTap: () => { void this.openSecretUrl(); } })
          }
          if (this.card.secretReference && !this.hasSecretFields() && this.connection.config.secretRequestReferences === true) {
            Row({ space: Space.xs }) {
              AppButton({ label: this.referenceMode ? '使用引用' : '直接输入', kind: 'text', compact: true,
                onTap: () => { this.referenceMode = !this.referenceMode; } })
            }.width('100%')
          }
          if (this.referenceMode && !this.hasSecretFields()) {
            if (this.secretProviders().length) {
              Text('来源').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.secretProviders(), (name: string) => {
                  Button(name, { type: ButtonType.Normal }).constraintSize({ minHeight: 38 }).fontSize(FontSize.callout)
                    .fontWeight(this.referenceProvider === name ? Weight.semibold : Weight.medium)
                    .margin({ right: Space.xs, bottom: Space.xs })
                    .backgroundColor(this.referenceProvider === name ? $r('app.color.info_bg') : $r('app.color.group'))
                    .fontColor(this.referenceProvider === name ? $r('app.color.primary_text') : $r('app.color.ink'))
                    .border({ width: Sizes.hairline, color: this.referenceProvider === name ? $r('app.color.primary') : Color.Transparent, radius: Radius.button })
                    .borderRadius(Radius.button)
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
          } else if (this.hasSecretFields()) {
            Column({ space: Space.xs }) {
              ForEach(this.card.secretFields, (field: SecretField) => {
                Column({ space: 4 }) {
                  Text(field.label)
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontWeight(Weight.medium)
                    .fontColor($r('app.color.muted'))
                    .width('100%')
                  if (field.secret) {
                    TextInput({ placeholder: field.placeholder, text: this.secretFieldText(field.name) })
                      .type(InputType.Password)
                      .showPasswordIcon(true)
                      .showPassword(this.isFieldVisible(field.name))
                      .onSecurityStateChange((visible: boolean) => this.setFieldVisible(field.name, visible))
                      .enableAutoFill(false)
                      .enabled(!this.busy && !this.submitted)
                      .fontSize(FontSize.body).constraintSize({ minHeight: 44 })
                      .backgroundColor($r('app.color.input_bg')).border({ width: 1, color: $r('app.color.input_border') })
                      .borderRadius(Radius.button)
                      .onChange((value: string) => this.setSecretFieldText(field.name, value))
                  } else {
                    TextInput({ placeholder: field.placeholder, text: this.secretFieldText(field.name) })
                      .type(InputType.Normal)
                      .enableAutoFill(false)
                      .enabled(!this.busy && !this.submitted)
                      .fontSize(FontSize.body).constraintSize({ minHeight: 44 })
                      .backgroundColor($r('app.color.input_bg')).border({ width: 1, color: $r('app.color.input_border') })
                      .borderRadius(Radius.button)
                      .onChange((value: string) => this.setSecretFieldText(field.name, value))
                  }
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }, (field: SecretField) => this.card.id + ':' + field.name)
            }
            .width('100%')
            AppButton({ label: '安全提交', kind: 'primary', compact: true, fill: true,
              disabled: this.busy || this.submitted || !this.allSecretFieldsFilled(),
              onTap: () => { void this.submit(''); } })
          } else {
            TextInput({ placeholder: this.card.secretPlaceholder || '敏感输入', text: this.secretValue })
              .type(InputType.Password)
              .showPasswordIcon(true)
              .showPassword(this.secretVisible)
              .onSecurityStateChange((visible: boolean) => { this.secretVisible = visible; })
              .enableAutoFill(false)
              .enabled(!this.busy && !this.submitted)
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
        ForEach(questionDisplays(this.card.questions), (display: QuestionDisplay) => {
          Column({ space: Space.xs }) {
            if (!display.companion && display.ordinal > 1) {
              Divider()
                .color($r('app.color.separator'))
                .strokeWidth(Sizes.hairline)
                .margin({ top: Space.xs, bottom: Space.xs })
            }
            if (display.companion) {
              Row({ space: Space.xs }) {
                Text(this.hasCustomText(display.question) ? '补充说明（已填写）' : display.title)
                  .fontSize(FontSize.caption)
                  .lineHeight(LineHeight.caption)
                  .fontWeight(Weight.medium)
                  .fontColor(this.hasCustomText(display.question) ? $r('app.color.primary_text') : $r('app.color.muted'))
                  .layoutWeight(1)
                Row({ space: 4 }) {
                  Image($r('app.media.ui_plus'))
                    .width(12)
                    .height(12)
                    .opacity(0.75)
                    .accessibilityLevel('no')
                  Text(this.uploadBusy === display.question.id ? '上传中…' : '附件')
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontWeight(Weight.medium)
                    .fontColor($r('app.color.muted'))
                }
                .padding({ left: Space.xs, right: Space.xs, top: 4, bottom: 4 })
                .borderRadius(Radius.badge)
                .backgroundColor($r('app.color.group'))
                .enabled(!this.busy && !this.submitted && this.uploadBusy !== display.question.id)
                .opacity(this.busy || this.submitted || this.uploadBusy === display.question.id ? Opacity.disabled : 1)
                .accessibilityText('添加补充说明附件')
                .onClick(() => { void this.addQuestionAttachment(display.question); })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: Space.xxs })
            } else {
              if (display.eyebrow.length > 0) {
                Text(display.eyebrow)
                  .fontSize(FontSize.caption)
                  .lineHeight(LineHeight.caption)
                  .fontWeight(Weight.medium)
                  .fontColor($r('app.color.muted'))
                  .width('100%')
              }
              Row({ space: Space.xs }) {
                Text((display.primaryTotal > 1 ? display.ordinal + '. ' : '') + display.title)
                  .fontSize(FontSize.body)
                  .lineHeight(LineHeight.body)
                  .fontWeight(Weight.semibold)
                  .fontColor($r('app.color.ink'))
                  .layoutWeight(1)
                Row({ space: Space.xxs }) {
                  if (display.question.multi) {
                    StatusBadge({ text: '多选', tone: 'neutral' })
                  }
                  if (this.questionAnswered(display.question)) {
                    StatusBadge({
                      text: this.hasCustomText(display.question) ? '已填' : '已选',
                      tone: 'success'
                    })
                  } else if (display.question.required) {
                    StatusBadge({ text: '必填', tone: 'warning' })
                  } else {
                    StatusBadge({ text: '可选', tone: 'neutral' })
                  }
                }
                .flexShrink(0)
                .margin({ top: 2 })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }
            if (display.question.optionItems.length > 0) {
              Column({ space: Space.xs }) {
                ForEach(display.question.optionItems, (opt: QuestionOption, idx: number) => {
                  Column({ space: Space.xxs }) {
                    Row({ space: Space.sm }) {
                      Stack({ alignContent: Alignment.Center }) {
                        if (this.selected(display.question, opt.value)) {
                          Text('✓')
                            .fontSize(FontSize.badge)
                            .fontWeight(Weight.bold)
                            .fontColor($r('app.color.on_primary_fill'))
                            .accessibilityLevel('no')
                        }
                      }
                      .width(18)
                      .height(18)
                      .margin({ top: 2 })
                      .flexShrink(0)
                      .borderRadius(display.question.multi ? 5 : Radius.full)
                      .backgroundColor(this.selected(display.question, opt.value) ? $r('app.color.primary') : Color.Transparent)
                      .border({
                        width: this.selected(display.question, opt.value) ? 0 : 1.5,
                        color: $r('app.color.chevron')
                      })
                      Column({ space: 4 }) {
                        Text(opt.label)
                          .fontSize(FontSize.body)
                          .lineHeight(LineHeight.body)
                          .fontWeight(this.selected(display.question, opt.value) ? Weight.medium : Weight.regular)
                          .fontColor(this.selected(display.question, opt.value) ? $r('app.color.primary_text') : $r('app.color.ink'))
                          .width('100%')
                        if (opt.description.length > 0) {
                          Text(opt.description)
                            .fontSize(FontSize.callout)
                            .lineHeight(LineHeight.callout)
                            .fontColor($r('app.color.muted'))
                            .width('100%')
                        }
                        if (opt.recommended) {
                          Text('推荐')
                            .fontSize(FontSize.badge)
                            .lineHeight(LineHeight.badge)
                            .fontWeight(Weight.medium)
                            .fontColor($r('app.color.primary_text'))
                            .backgroundColor(this.selected(display.question, opt.value) ? $r('app.color.card') : $r('app.color.info_bg'))
                            .borderRadius(Radius.badge)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            .margin({ top: 2 })
                        }
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .constraintSize({ minHeight: 46 })
                    .padding({ left: Space.sm, right: Space.sm, top: 11, bottom: 11 })
                    .alignItems(VerticalAlign.Top)
                    .backgroundColor(this.selected(display.question, opt.value) ? $r('app.color.info_bg') : $r('app.color.group'))
                    .borderRadius(Radius.button)
                    .border({
                      width: this.selected(display.question, opt.value) ? 1.5 : Sizes.hairline,
                      color: this.selected(display.question, opt.value) ? $r('app.color.primary') : $r('app.color.border_subtle')
                    })
                    .enabled(!this.busy && !this.submitted)
                    .opacity(this.busy || this.submitted ? Opacity.disabled : 1)
                    .accessibilityGroup(true)
                    .accessibilityText(opt.label + (opt.recommended ? '，推荐' : '') + (opt.description ? '，' + opt.description : '') + (this.selected(display.question, opt.value) ? '，已选中' : '，未选中'))
                    .onClick(() => this.choose(display.question, opt.value))
                    if (opt.preview.length > 0) {
                      Text(opt.preview)
                        .fontSize(FontSize.mono)
                        .lineHeight(LineHeight.mono)
                        .fontFamily('monospace')
                        .fontColor($r('app.color.ink'))
                        .width('100%')
                        .padding(Space.xs)
                        .backgroundColor($r('app.color.group'))
                        .borderRadius(Radius.tool)
                    }
                  }
                  .width('100%')
                }, (opt: QuestionOption, idx: number) => display.question.id + ':' + idx + ':' + opt.value)
              }
              .width('100%')
            }
            if (display.question.custom) {
              if (!display.companion) {
                Row({ space: Space.xs }) {
                  Text(display.question.optionItems.length > 0 ? '自定义回答' : '输入回答')
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontWeight(Weight.medium)
                    .fontColor($r('app.color.muted'))
                    .layoutWeight(1)
                  Row({ space: 4 }) {
                    Image($r('app.media.ui_plus'))
                      .width(12)
                      .height(12)
                      .opacity(0.75)
                      .accessibilityLevel('no')
                    Text(this.uploadBusy === display.question.id ? '上传中…' : '附件')
                      .fontSize(FontSize.caption)
                      .lineHeight(LineHeight.caption)
                      .fontWeight(Weight.medium)
                      .fontColor($r('app.color.muted'))
                  }
                  .padding({ left: Space.xs, right: Space.xs, top: 4, bottom: 4 })
                  .borderRadius(Radius.badge)
                  .backgroundColor($r('app.color.group'))
                  .enabled(!this.busy && !this.submitted && this.uploadBusy !== display.question.id)
                  .opacity(this.busy || this.submitted || this.uploadBusy === display.question.id ? Opacity.disabled : 1)
                  .accessibilityText('添加问题附件')
                  .onClick(() => { void this.addQuestionAttachment(display.question); })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .margin({ top: display.question.optionItems.length > 0 ? Space.xxs : 0 })
              }
              TextArea({ placeholder: display.placeholder, text: this.customText(display.question) })
                .width('100%')
                .constraintSize({ minHeight: 44 })
                .maxLines(4, { overflowMode: MaxLinesMode.SCROLL })
                .fontSize(FontSize.body)
                .lineHeight(LineHeight.body)
                .fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.placeholder'))
                .backgroundColor($r('app.color.input_bg'))
                .border({
                  width: 1,
                  color: this.hasCustomText(display.question) ? $r('app.color.primary') : $r('app.color.input_border')
                })
                .borderRadius(Radius.button)
                .padding({ left: Space.sm, right: Space.sm, top: 10, bottom: 10 })
                .enabled(!this.busy && !this.submitted)
                .onChange((value: string) => {
                  const prev = this.customAnswers.get(display.question.id) || '';
                  if (prev === value) return;
                  this.customAnswers.set(display.question.id, value);
                  this.customAnswers = new Map(this.customAnswers);
                })
            }
            if (this.questionAttachments(display.question.id).length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.questionAttachments(display.question.id), (item: DraftAttachment) => {
                  Row({ space: Space.xxs }) {
                    Text(item.name)
                      .fontSize(FontSize.caption)
                      .lineHeight(LineHeight.caption)
                      .fontColor($r('app.color.ink'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .constraintSize({ maxWidth: 200 })
                    Text('×')
                      .fontSize(FontSize.callout)
                      .fontColor($r('app.color.muted'))
                  }
                  .padding({ left: Space.xs, right: Space.xs, top: 4, bottom: 4 })
                  .margin({ right: Space.xs, bottom: Space.xs })
                  .borderRadius(Radius.badge)
                  .backgroundColor($r('app.color.group'))
                  .border({ width: Sizes.hairline, color: $r('app.color.border_subtle') })
                  .accessibilityText('移除附件：' + item.name)
                  .onClick(() => this.removeQuestionAttachment(display.question.id, item.id))
                }, (item: DraftAttachment) => display.question.id + ':' + item.id)
              }
              .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (display: QuestionDisplay) => display.question.id)
        Column({ space: Space.xs }) {
          AppButton({
            label: this.submitted ? '已提交回答' : '提交回答',
            kind: this.allRequiredAnswered() ? 'primary' : 'secondary',
            compact: true,
            fill: true,
            loading: this.busy,
            disabled: !this.card.enabled || this.busy || this.submitted,
            onTap: () => { void this.submit(''); }
          })
          if (this.card.canDismiss) {
            AppButton({
              label: '关闭问题',
              kind: 'text',
              compact: true,
              fill: true,
              disabled: this.busy || this.submitted,
              onTap: () => { void this.dismiss(); }
            })
          }
        }
        .width('100%')
        .margin({ top: Space.xs })
      }
      if (!this.card.enabled) {
        Text('此请求不可恢复，请停止后重新发起任务').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
      }
      if (this.status) {
        Text(this.status)
          .fontSize(FontSize.callout)
          .lineHeight(LineHeight.callout)
          .fontColor(this.statusColorOf())
          .width('100%')
      }
    }.padding(Space.md).width('100%').alignItems(HorizontalAlign.Start)
      .backgroundColor(this.card.kind === 'approval' ? $r('app.color.warning_bg') : $r('app.color.card'))
      .foregroundColor($r('app.color.ink')).borderRadius(Radius.card)
      .border({ width: 1, color: this.card.kind === 'approval' ? $r('app.color.warning_border') : $r('app.color.border') })
  }
}
