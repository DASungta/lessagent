import { util } from '@kit.ArkTS';
import { TerminalGrid, TerminalSize, TerminalSessions, TerminalSessionSummary, terminalSessions, newTerminalId, terminalSnapshot,
  DEFAULT_TERMINAL_FONT_SIZE, MIN_TERMINAL_FONT_SIZE, MAX_TERMINAL_FONT_SIZE, terminalCanvasSize, terminalFitSize } from '../protocol/Terminal';
import { record, text } from '../protocol/Wire';
import { setTerminalFontSize, workspacePrefs } from '../services/WorkspacePrefs';

@Component
export struct TerminalPanel {
  @Prop threadId: string = '';
  @Prop initialTerminalId: string = '';
  @StorageLink('t3Foreground') @Watch('foregroundChanged') foreground: boolean = true;
  canOperate: () => boolean = () => false;
  watchTerminals: (receive: (value: Object) => void, failed: (message: string) => void) => (() => void) =
    () => { throw new Error('终端列表尚未接入'); };
  attach: (terminalId: string, size: TerminalSize, resume: boolean, receive: (value: Object) => void,
    failed: (message: string) => void) => (() => void) = () => () => {};
  write: (terminalId: string, data: string) => Promise<void> = async () => {};
  reply: (terminalId: string, data: string) => Promise<void> = async () => { throw new Error('终端查询应答尚未接入'); };
  resize: (terminalId: string, size: TerminalSize) => Promise<void> = async () => {};
  closeTerminal: (terminalId: string) => Promise<void> = async () => {};
  onBack: () => void = () => {};
  onCopy: (value: string) => Promise<void> = async () => { throw new Error('复制尚未接入'); };
  @State readingOffset: number = 0;
  @State maxReadingOffset: number = 0;
  @State historyTruncated: boolean = false;
  @State copyNotice: string = '';
  @State copying: boolean = false;
  @State selectionText: string = '';
  private copyGeneration: number = 0;
  @State status: string = '正在读取终端列表';
  @State terminalId: string = '';
  @State sessions: TerminalSessions = { loaded: false, terminals: [] };
  @State listError: string = '';
  private pendingTerminalId: string = '';
  private metadataCancel: (() => void) | undefined = undefined;
  private metadataGeneration: number = 0;
  @State error: string = '';
  @State input: string = '';
  @State active: boolean = false;
  @State busy: boolean = false;
  @State limited: boolean = false;
  @State appendEnter: boolean = true;
  @State fontSize: number = DEFAULT_TERMINAL_FONT_SIZE;
  @State fontSaving: boolean = false;
  private grid: TerminalGrid = new TerminalGrid(40, 24);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private cancel: (() => void) | undefined = undefined;
  private sequence: number = -1;
  private replyQueue: string[] = [];
  private replying: boolean = false;
  private generation: number = 0;
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private cellWidth: number = 8.4;
  private cellHeight: number = 20;
  private canvasReady: boolean = false;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true; this.fontSize = workspacePrefs.terminalFontSize;
    this.measureCells();
    this.terminalId = this.initialTerminalId; this.loadSessions();
  }
  aboutToDisappear(): void { this.alive = false; this.stopMetadata(); this.disconnect(); }
  private foregroundChanged(): void {
    if (this.foreground) return;
    this.stopMetadata(); this.disconnect();
    this.sessions = { loaded: false, terminals: this.sessions.terminals };
    this.status = '应用进入后台，查看已断开；返回后请更新列表并连接';
  }
  private stopMetadata(): void {
    this.metadataGeneration++;
    this.metadataCancel?.(); this.metadataCancel = undefined;
  }
  private loadSessions(): void {
    if (!this.foreground) return;
    this.stopMetadata(); this.listError = '';
    this.sessions = { loaded: false, terminals: this.sessions.terminals };
    const generation = this.metadataGeneration;
    try {
      const cancel = this.watchTerminals((value: Object): void => {
        if (generation !== this.metadataGeneration || !this.foreground) return;
        try {
          const next = terminalSessions(this.sessions, value, this.threadId);
          this.sessions = next;
          if (this.pendingTerminalId && next.terminals.some((item: TerminalSessionSummary): boolean => item.terminalId === this.pendingTerminalId)) {
            this.pendingTerminalId = '';
          }
          if (this.terminalId && this.terminalId !== this.pendingTerminalId &&
            !next.terminals.some((item: TerminalSessionSummary): boolean => item.terminalId === this.terminalId)) {
            this.disconnect(); this.terminalId = ''; this.clearDisplay(); this.status = '所选终端已关闭';
          }
          if (!this.terminalId && next.terminals.length) {
            const selected = next.terminals.find((item: TerminalSessionSummary): boolean => item.status === 'running') || next.terminals[0];
            this.selectSession(selected.terminalId);
          } else if (!this.terminalId) this.status = '此会话没有终端，点击新建开始';
        } catch (reason) { this.metadataFailed((reason as Error).message, generation); }
      }, (message: string): void => this.metadataFailed(message, generation));
      if (generation === this.metadataGeneration) this.metadataCancel = cancel; else cancel();
    } catch (reason) { this.metadataFailed((reason as Error).message, generation); }
  }
  private metadataFailed(message: string, generation: number): void {
    if (generation !== this.metadataGeneration) return;
    this.stopMetadata(); this.sessions = { loaded: false, terminals: this.sessions.terminals };
    this.listError = message + '。列表状态未确认，请更新后重试。';
  }
  private disconnect(): void {
    this.generation++; this.busy = false; this.copyGeneration++; this.copying = false;
    this.selectionText = ''; this.copyNotice = '';
    this.replyQueue = []; this.replying = false;
    if (this.cancel) this.cancel();
    this.cancel = undefined; this.active = false;
  }
  private clearDisplay(): void {
    this.readingOffset = 0; this.copyNotice = '';
    this.input = ''; this.sequence = -1; this.grid.reset(); this.limited = false; this.error = ''; this.draw();
  }
  private selectSession(terminalId: string): void {
    if (this.busy || !this.foreground || !this.sessions.loaded || terminalId === this.terminalId ||
      !this.sessions.terminals.some((item: TerminalSessionSummary): boolean => item.terminalId === terminalId)) return;
    this.disconnect(); this.terminalId = terminalId; this.pendingTerminalId = ''; this.clearDisplay();
    this.status = '已选择终端，点击连接查看';
  }
  private createSession(): void {
    if (this.busy || !this.foreground || !this.sessions.loaded || !this.canOperate()) return;
    const ids = this.sessions.terminals.map((item: TerminalSessionSummary): string => item.terminalId);
    if (this.terminalId) ids.push(this.terminalId);
    const terminalId = newTerminalId(ids, util.generateRandomUUID());
    this.disconnect(); this.terminalId = terminalId; this.pendingTerminalId = terminalId; this.clearDisplay();
    this.status = '新终端已准备，点击连接启动 shell';
  }
  private connect(resume: boolean = true): void {
    if (this.busy || !this.foreground || !this.sessions.loaded || !this.terminalId) return;
    if ((!resume || this.pendingTerminalId === this.terminalId) && !this.canOperate()) return;
    const size = terminalFitSize(this.viewportSize());
    if (!size) { this.error = '显示空间不足，请缩小终端字号或扩大窗口'; return; }
    this.disconnect(); this.readingOffset = 0; this.copyNotice = ''; this.error = ''; this.status = '正在连接…'; this.sequence = -1; this.draw();
    const generation = this.generation; const terminalId = this.terminalId;
    try {
      const cancel = this.attach(terminalId, size, resume,
        (value: Object): void => { if (generation === this.generation && terminalId === this.terminalId) this.receive(value); },
        (message: string): void => {
          if (generation !== this.generation || terminalId !== this.terminalId) return;
          this.disconnect(); this.error = message; this.status = '连接中断，重新连接后核对输出';
        });
      if (generation === this.generation) this.cancel = cancel; else cancel();
    } catch (reason) { this.error = (reason as Error).message; }
  }
  private restart(): void {
    if (this.busy || !this.restartable() || !this.canOperate() || !this.sessions.loaded) return;
    const terminalId = this.terminalId; const generation = this.generation;
    AlertDialog.show({ title: '重新启动终端？', message: '将在此终端启动新的 shell，已退出的进程不会恢复。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '重新启动', action: () => {
        if (generation === this.generation && terminalId === this.terminalId) this.connect(false);
      } } });
  }
  private receive(value: Object): void {
    try {
      const event = record(value);
      const kind = text(event.type);
      if (kind !== 'snapshot' && (event.threadId !== this.threadId || event.terminalId !== this.terminalId)) return;
      if (kind === 'snapshot' || kind === 'restarted') {
        const snapshot = terminalSnapshot(record(event.snapshot), this.threadId, this.terminalId);
        this.sequence = snapshot.sequence;
        this.closeTextSelection();
        this.readingOffset = 0; this.copyNotice = ''; this.grid.reset();
        if (snapshot.size) this.grid.resize(snapshot.size.cols, snapshot.size.rows);
        this.grid.feed(snapshot.history, false);
        this.grid.takeReplies(); // Historical terminal queries must never be sent again.
        this.active = snapshot.status === 'running' || snapshot.status === 'starting';
        this.status = snapshot.status === 'running' ? '运行中' : snapshot.status === 'starting' ? '启动中' : '已退出';
        this.error = snapshot.error;
      } else {
        if (typeof event.sequence === 'number') {
          if (event.sequence <= this.sequence) return;
          if (this.sequence >= 0 && event.sequence !== this.sequence + 1) {
            this.disconnect(); throw new Error('终端输出不连续，请重新连接获取快照');
          }
          this.sequence = event.sequence;
        }
        if (kind === 'output') {
          const before = this.grid.view(this.readingOffset, this.visibleRows()).endLine; const alternate = this.grid.alternate;
          this.grid.feed(text(event.data));
          const after = this.grid.view(this.readingOffset, this.visibleRows()).endLine;
          if (alternate !== this.grid.alternate || after < before) this.readingOffset = 0;
          else if (this.readingOffset > 0) this.readingOffset += after - before;
          this.syncReading();
          const replies = this.grid.takeReplies();
          if (replies.length && this.canOperate()) this.queueQueries(replies);
        }
        else if (kind === 'cleared') { this.closeTextSelection(); this.grid.reset(); this.readingOffset = 0; this.copyNotice = ''; }
        else if (kind === 'exited' || kind === 'closed') { this.disconnect(); this.status = kind === 'exited' ? '已退出' : '已关闭'; }
        else if (kind === 'error') { this.disconnect(); this.error = text(event.message); }
        else if (kind === 'activity' && typeof event.cols === 'number' && typeof event.rows === 'number') this.grid.resize(event.cols, event.rows);
      }
      this.limited = this.grid.unsupported; this.draw();
    } catch (reason) { this.disconnect(); this.error = (reason as Error).message; }
  }
  private queueQueries(values: string[]): void {
    if (this.replyQueue.length + values.length > 16) {
      this.disconnect(); throw new Error('终端查询过于频繁，请重新连接后核对');
    }
    this.replyQueue.push(...values);
    if (!this.replying) void this.answerQueries();
  }
  private async answerQueries(): Promise<void> {
    const generation = this.generation; const terminalId = this.terminalId;
    this.replying = true;
    try {
      while (this.replyQueue.length && generation === this.generation) {
        const value = this.replyQueue.shift();
        if (value && this.canOperate() && this.foreground) await this.reply(terminalId, value);
      }
    } catch (reason) {
      if (generation === this.generation) { this.disconnect(); this.error = (reason as Error).message; }
    } finally { if (generation === this.generation) this.replying = false; }
  }
  private viewportSize(): TerminalSize {
    return terminalCanvasSize(this.canvasWidth, this.canvasHeight, this.cellWidth, this.cellHeight);
  }
  private visibleRows(): number { return Math.max(1, Math.min(this.grid.rows, this.viewportSize().rows)); }
  private measureCells(): void {
    this.cellWidth = this.fontSize * 0.6;
    this.cellHeight = Math.ceil(this.fontSize * 20 / 14);
    if (!this.canvasReady) return;
    this.context.font = this.fontSize + 'vp monospace';
    const measured = this.context.measureText('MMMMMMMMMM').width / 10;
    if (Number.isFinite(measured) && measured > 0) this.cellWidth = measured;
  }
  private async changeFontSize(delta: number): Promise<void> {
    const size = this.fontSize + delta;
    if (!this.alive || !this.foreground || this.fontSaving || this.busy ||
      size < MIN_TERMINAL_FONT_SIZE || size > MAX_TERMINAL_FONT_SIZE) return;
    this.fontSaving = true;
    const generation = this.generation;
    try {
      await setTerminalFontSize(size);
      if (!this.alive) return;
      this.fontSize = size;
      this.closeTextSelection();
      this.measureCells();
      this.draw();
      if (generation === this.generation && this.active && this.canOperate() && this.foreground) await this.fit();
    } catch (_) {
      if (this.alive) this.error = '终端字号保存失败，请重试';
    } finally { this.fontSaving = false; }
  }
  private pageText(): string {
    const viewport = this.viewportSize();
    return viewport.rows === 0 || viewport.cols === 0 ? '' :
      this.grid.viewText(this.readingOffset, this.visibleRows(), viewport.cols);
  }
  private syncReading(): void {
    const view = this.grid.view(this.readingOffset, this.visibleRows());
    this.readingOffset = view.offset; this.maxReadingOffset = view.maxOffset;
    this.historyTruncated = this.grid.historyTruncated;
  }
  private readPage(direction: number): void {
    if (!this.foreground || !this.terminalId) return;
    this.closeTextSelection();
    this.readingOffset = Math.max(0, this.readingOffset + direction * Math.max(1, this.visibleRows() - 1));
    this.syncReading(); this.copyNotice = ''; this.draw();
  }
  private readLatest(): void {
    if (!this.foreground) return;
    this.closeTextSelection();
    this.readingOffset = 0; this.copyNotice = ''; this.draw();
  }
  private selectVisibleText(): void {
    if (!this.foreground || !this.terminalId || this.copying || this.selectionText) return;
    this.copyNotice = '';
    try {
      const value = this.pageText();
      if (value.trim()) this.selectionText = value;
      else this.copyNotice = '当前页没有可选择的文字';
    } catch (_) {
      this.copyNotice = '当前页文字过多，请缩小终端尺寸后重试';
    }
  }
  private closeTextSelection(): void {
    if (!this.selectionText) return;
    this.selectionText = ''; this.copyNotice = '';
    this.copyGeneration++; this.copying = false;
  }
  private async copyVisible(fromSelection: boolean = false): Promise<void> {
    if (!this.foreground || !this.terminalId || this.copying || (fromSelection && !this.selectionText)) return;
    const generation = this.generation; const terminalId = this.terminalId; const copy = ++this.copyGeneration;
    this.copying = true; this.copyNotice = '';
    try {
      const value = fromSelection ? this.selectionText : this.pageText();
      if (!value.trim()) { this.copyNotice = '当前页没有可复制的文字'; return; }
      await this.onCopy(value);
      if (this.foreground && generation === this.generation && terminalId === this.terminalId && copy === this.copyGeneration) {
        this.copyNotice = '当前页已复制';
      }
    } catch (_) {
      if (this.foreground && generation === this.generation && terminalId === this.terminalId && copy === this.copyGeneration) {
        this.copyNotice = '复制失败，请重试';
      }
    } finally { if (copy === this.copyGeneration) this.copying = false; }
  }
  private draw(): void {
    this.syncReading();
    const ctx = this.context;
    ctx.fillStyle = '#16181d'; ctx.fillRect(0, 0, this.canvasWidth, this.canvasHeight);
    const size = this.viewportSize();
    if (size.rows === 0 || size.cols === 0) return;
    const view = this.grid.view(this.readingOffset, this.visibleRows());
    const cw = this.cellWidth;
    const ch = this.cellHeight;
    const font = this.fontSize + 'vp monospace';
    ctx.font = font; ctx.textBaseline = 'top';
    for (let y = 0; y < view.rows.length; y++) for (let x = 0; x < Math.min(size.cols, view.rows[y].length); x++) {
      const cell = view.rows[y][x];
      ctx.fillStyle = cell.background; ctx.fillRect(x * cw, y * ch, cw, ch);
    }
    for (let y = 0; y < view.rows.length; y++) for (let x = 0; x < Math.min(size.cols, view.rows[y].length); x++) {
      const cell = view.rows[y][x];
      if (!cell.char || cell.hidden) continue;
      ctx.font = (cell.bold ? 'bold ' : '') + font;
      ctx.globalAlpha = cell.dim ? 0.55 : 1;
      ctx.fillStyle = cell.color; ctx.fillText(cell.char, x * cw, y * ch);
      if (cell.underline) ctx.fillRect(x * cw, (y + 1) * ch - 2, cw, 1);
    }
    ctx.globalAlpha = 1;
    if (this.readingOffset === 0 && this.grid.cursorVisible && view.cursorRow >= 0 && this.grid.x < size.cols) {
      ctx.fillStyle = '#82aaff'; ctx.fillRect(Math.min(this.grid.x, this.grid.cols - 1) * cw, (view.cursorRow + 1) * ch - 2, cw, 2);
    }
  }
  private async send(data: string): Promise<void> {
    if (!this.active || this.busy || !data || !this.foreground || !this.canOperate()) return;
    const generation = this.generation; const terminalId = this.terminalId;
    this.busy = true; this.error = '';
    try { await this.write(terminalId, data); }
    catch (reason) {
      if (generation !== this.generation || terminalId !== this.terminalId) return;
      this.active = false;
      this.error = (reason as Error).message + '。输入结果未知，不会自动重发；重新连接后核对。';
    } finally { if (generation === this.generation) this.busy = false; }
  }
  private keyMenu(terminalId: string, generation: number): MenuElement[] {
    const send = (key: string): void => {
      if (this.terminalId === terminalId && this.generation === generation) void this.send(key);
    };
    return [
      { value: 'Tab', action: () => send('\t') },
      { value: '左方向键', action: () => send(this.grid.cursorKey('D')) },
      { value: '右方向键', action: () => send(this.grid.cursorKey('C')) },
      { value: 'Page Up', action: () => send('\x1b[5~') },
      { value: 'Page Down', action: () => send('\x1b[6~') }
    ];
  }
  private async submit(): Promise<void> {
    const value = this.input;
    if (!value || !this.active || this.busy || !this.foreground || !this.canOperate()) return;
    this.input = '';
    await this.send(value + (this.appendEnter ? '\r' : ''));
  }
  private async fit(): Promise<void> {
    if (!this.active || this.busy || !this.foreground || !this.canOperate()) return;
    const generation = this.generation; const terminalId = this.terminalId;
    const size = terminalFitSize(this.viewportSize());
    if (!size) { this.error = '显示空间不足，保留原终端尺寸'; return; }
    if (size.cols === this.grid.cols && size.rows === this.grid.rows) return;
    this.error = '';
    this.busy = true;
    try {
      await this.resize(terminalId, size);
      if (generation === this.generation && terminalId === this.terminalId) {
        if (size.cols !== this.grid.cols || size.rows !== this.grid.rows) this.grid.resize(size.cols, size.rows);
        this.draw();
      }
    } catch (reason) { if (generation === this.generation) this.error = (reason as Error).message; }
    finally { if (generation === this.generation) this.busy = false; }
  }
  private stop(): void {
    if (this.busy || !this.terminalId || !this.canOperate()) return;
    const terminalId = this.terminalId; const generation = this.generation;
    AlertDialog.show({ title: '结束所选终端？', message: '仅结束此终端的 shell 及其任务，保留历史。其他终端继续运行。返回页面不会结束任务。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '结束', action: () => { void this.stopConfirmed(terminalId, generation); } } });
  }
  private async stopConfirmed(terminalId: string, generation: number): Promise<void> {
    if (this.busy || !this.foreground || !this.canOperate() || terminalId !== this.terminalId || generation !== this.generation) return;
    this.busy = true;
    try {
      await this.closeTerminal(terminalId);
      if (generation !== this.generation || terminalId !== this.terminalId) return;
      this.disconnect(); this.terminalId = ''; this.pendingTerminalId = ''; this.clearDisplay(); this.status = '所选终端已结束';
      this.sessions = { loaded: this.sessions.loaded,
        terminals: this.sessions.terminals.filter((item: TerminalSessionSummary): boolean => item.terminalId !== terminalId) };
    } catch (reason) {
      if (generation === this.generation) this.error = (reason as Error).message + '。结束结果未知，请更新列表核对。';
    } finally { if (generation === this.generation) this.busy = false; }
  }
  private restartable(): boolean {
    const item = this.sessions.terminals.find((item: TerminalSessionSummary): boolean => item.terminalId === this.terminalId);
    return !!item && !this.active && (item.status === 'exited' || item.status === 'error');
  }
  private selectedLabel(): string {
    const item = this.sessions.terminals.find((item: TerminalSessionSummary): boolean => item.terminalId === this.terminalId);
    return item ? item.label : this.pendingTerminalId ? '新终端（未启动）' : '选择终端';
  }
  private sessionLabel(item: TerminalSessionSummary): string {
    const state = item.status === 'running' ? item.hasRunningSubprocess ? '任务运行中' : '就绪' :
      item.status === 'starting' ? '启动中' : item.status === 'exited' ? '已退出' : '异常';
    return item.label + ' · ' + state;
  }
  private readingNotice(): string {
    const reading = this.selectionText ? '当前页快照 · 长按文字选择' :
      this.readingOffset > 0 ? '阅读历史 · 距底部 ' + this.readingOffset + ' 行' : '跟随最新输出';
    return reading + (!this.selectionText && this.historyTruncated ? ' · 更早历史已达本地保留上限' : '') +
      (this.copyNotice ? ' · ' + this.copyNotice : '');
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Button('返回', { type: ButtonType.Normal }).height(44).constraintSize({ minWidth: 44 })
          .backgroundColor(Color.Transparent).fontColor($r('app.color.ink')).borderRadius(12).onClick(() => this.onBack())
        Text('终端').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1).margin({ left: 12 })
        Button(this.active ? '重新连接' : '连接').height(44)
          .backgroundColor(this.active ? $r('app.color.surface') : $r('app.color.primary')).fontColor(this.active ? $r('app.color.ink') : $r('app.color.on_primary')).enabled(!this.busy && this.foreground && this.sessions.loaded && !!this.terminalId).onClick(() => this.connect())
      }.width('100%')
      Row({ space: 8 }) {
        Select(this.sessions.terminals.map((item: TerminalSessionSummary): SelectOption => ({ value: this.sessionLabel(item) })))
          .value(this.selectedLabel()).height(44).layoutWeight(1)
          .enabled(this.foreground && this.sessions.loaded && !this.busy && this.sessions.terminals.length > 0)
          .onSelect((index: number) => { if (this.sessions.terminals[index]) this.selectSession(this.sessions.terminals[index].terminalId); })
        Button('更新', { type: ButtonType.Normal }).height(44).backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.ink')).enabled(this.foreground && !this.busy).onClick(() => this.loadSessions())
        Button('新建', { type: ButtonType.Normal }).height(44).backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.ink')).enabled(this.foreground && this.sessions.loaded && !this.busy && this.canOperate())
          .onClick(() => this.createSession())
      }.width('100%')
      if (this.listError) Text(this.listError).fontSize(13).fontColor($r('app.color.danger'))
      if (!this.canOperate()) Text('只读查看 · 无法新建、输入或结束终端').fontSize(12).fontColor($r('app.color.muted'))
      if (this.restartable() && this.canOperate()) {
        Button('重新启动所选终端', { type: ButtonType.Normal }).height(44).backgroundColor(Color.Transparent)
          .fontColor($r('app.color.ink')).enabled(this.sessions.loaded && !this.busy && this.foreground).onClick(() => this.restart())
      }
      Row({ space: 6 }) {
        Text(this.status + ' · 字号 ' + this.fontSize).fontSize(12).layoutWeight(1)
          .fontColor($r('app.color.muted')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('A−').constraintSize({ minWidth: 44, minHeight: 44 }).accessibilityText('缩小终端字号')
          .enabled(this.foreground && !this.busy && !this.fontSaving && this.fontSize > MIN_TERMINAL_FONT_SIZE)
          .onClick(() => { void this.changeFontSize(-1); })
        Button('A+').constraintSize({ minWidth: 44, minHeight: 44 }).accessibilityText('放大终端字号')
          .enabled(this.foreground && !this.busy && !this.fontSaving && this.fontSize < MAX_TERMINAL_FONT_SIZE)
          .onClick(() => { void this.changeFontSize(1); })
      }.width('100%')
      Text('切换只断开查看，终端任务继续运行').fontSize(12).fontColor($r('app.color.muted'))
      if (this.error) Text(this.error).fontSize(13).fontColor($r('app.color.danger'))
      if (this.limited) Text('输出包含未支持的控制序列，画面可能不完整。').fontSize(12).fontColor($r('app.color.muted'))
      Stack() {
        Canvas(this.context).width('100%').height('100%').backgroundColor('#16181d')
          .onReady(() => { this.canvasReady = true; this.measureCells(); this.draw(); })
          .onAreaChange((_, area: Area) => { this.canvasWidth = Number(area.width); this.canvasHeight = Number(area.height); this.draw(); })
          .accessibilityLevel(this.selectionText ? 'no' : 'auto')
          .accessibilityText('终端输出；可打开文字工具选择本页文字')
        if (this.selectionText) {
          Scroll() {
            Text(this.selectionText).copyOption(CopyOptions.LocalDevice).width('100%')
              .fontFamily('monospace').fontSize(this.fontSize + 'vp').fontColor($r('app.color.ink'))
          }.padding(8).width('100%').height('100%').align(Alignment.TopStart).backgroundColor($r('app.color.surface'))
        }
      }.width('100%').layoutWeight(1).borderRadius(12).clip(true)
      if (this.selectionText) {
        Row({ space: 6 }) {
          Button('关闭选字', { type: ButtonType.Normal }).constraintSize({ minWidth: 44, minHeight: 44 }).fontSize(14)
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(10)
            .onClick(() => this.closeTextSelection())
          Blank()
          Button('复制全部', { type: ButtonType.Normal }).constraintSize({ minWidth: 44, minHeight: 44 }).fontSize(14)
            .backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary')).borderRadius(10)
            .enabled(!this.copying).onClick(() => { void this.copyVisible(true); })
        }.width('100%')
      } else {
        Row({ space: 6 }) {
          Button('上页', { type: ButtonType.Normal }).height(44).layoutWeight(1).fontSize(14).padding({ left: 4, right: 4 })
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
            .enabled(this.foreground && this.readingOffset < this.maxReadingOffset).onClick(() => this.readPage(1))
          Button('下页', { type: ButtonType.Normal }).height(44).layoutWeight(1).fontSize(14).padding({ left: 4, right: 4 })
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
            .enabled(this.foreground && this.readingOffset > 0).onClick(() => this.readPage(-1))
          Button('回到底部', { type: ButtonType.Normal }).height(44).layoutWeight(1).fontSize(14).padding({ left: 4, right: 4 })
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
            .enabled(this.foreground && this.readingOffset > 0).onClick(() => this.readLatest())
          Button('文字工具', { type: ButtonType.Normal }).height(44).layoutWeight(1).fontSize(14).padding({ left: 4, right: 4 })
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
            .enabled(this.foreground && !!this.terminalId && !this.copying && !this.selectionText)
            .bindMenu([
              { value: '选择文字', action: () => this.selectVisibleText() },
              { value: '复制本页', action: () => { void this.copyVisible(); } }
            ])
        }.width('100%')
      }
      Text(this.readingNotice())
          .fontSize(12).fontColor($r('app.color.muted')).width('100%')
      Row({ space: 8 }) {
        Button('Ctrl C', { type: ButtonType.Normal }).height(44).layoutWeight(1)
          .constraintSize({ minWidth: 44 }).padding({ left: 4, right: 4 }).fontSize(13)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(10).enabled(this.active && !this.busy && this.foreground && this.canOperate()).onClick(() => { void this.send('\x03'); })
        Button('按键', { type: ButtonType.Normal }).height(44).layoutWeight(1)
          .constraintSize({ minWidth: 44 }).padding({ left: 4, right: 4 }).fontSize(13)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(10).enabled(this.active && !this.busy && this.foreground && this.canOperate()).accessibilityText('发送终端按键').bindMenu(this.keyMenu(this.terminalId, this.generation))
        Button('↑', { type: ButtonType.Normal }).height(44).layoutWeight(1)
          .constraintSize({ minWidth: 44 }).padding({ left: 4, right: 4 }).fontSize(13)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(10).enabled(this.active && !this.busy && this.foreground && this.canOperate()).onClick(() => { void this.send(this.grid.cursorKey('A')); })
        Button('适配', { type: ButtonType.Normal }).height(44).layoutWeight(1)
          .constraintSize({ minWidth: 44 }).padding({ left: 4, right: 4 }).fontSize(13)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(10).enabled(this.active && !this.busy && this.foreground && this.canOperate()).onClick(() => { void this.fit(); })
        Button('结束', { type: ButtonType.Normal }).height(44).layoutWeight(1)
          .constraintSize({ minWidth: 44 }).padding({ left: 4, right: 4 }).fontSize(13)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(10).enabled(!!this.terminalId && !this.busy && this.foreground && this.canOperate()).onClick(() => this.stop())
      }.width('100%')
      Row({ space: 8 }) {
        Button('Esc', { type: ButtonType.Normal }).height(44).layoutWeight(1)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(10)
          .onClick(() => { void this.send('\x1b'); })
        Button('↓', { type: ButtonType.Normal }).height(44).layoutWeight(1)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(10)
          .onClick(() => { void this.send(this.grid.cursorKey('B')); })
        Button('↵', { type: ButtonType.Normal }).height(44).layoutWeight(1)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(10)
          .onClick(() => { void this.send('\r'); })
        Button(this.appendEnter ? '附带回车：开' : '附带回车：关', { type: ButtonType.Normal }).height(44).layoutWeight(2)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(10)
          .onClick(() => { this.appendEnter = !this.appendEnter; })
      }.width('100%').enabled(this.active && !this.busy && this.foreground && this.canOperate())
      Row({ space: 8 }) {
        TextInput({ placeholder: '输入文字，确认后发送', text: this.input }).layoutWeight(1)
          .onChange((value: string) => { this.input = value; }).onSubmit(() => { void this.submit(); })
        Button('发送').height(44).backgroundColor($r('app.color.primary'))
          .fontColor($r('app.color.on_primary')).enabled(this.active && !this.busy && this.foreground && this.canOperate() && this.input.length > 0).onClick(() => { void this.submit(); })
      }
    }.padding(16).width('100%').height('100%').backgroundColor($r('app.color.canvas'))
  }
}
