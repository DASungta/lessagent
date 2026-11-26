import { image } from '@kit.ImageKit';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { AppButton } from './ui/AppButton';
import { TopBar } from './ui/TopBar';
import { PreviewStream } from '../services/PreviewStream';
import { PreviewViewport, PreviewControl, PreviewTab, PreviewResizeViewport, PreviewResizeChoice, PreviewZoomResult,
  DEFAULT_PREVIEW_ZOOM_FACTOR, PREVIEW_RESIZE_CHOICES, PREVIEW_ZOOM_LEVELS, previewFrameMatchesViewport,
  previewHistory, previewPoint, previewMouse, previewKey, previewNavigation } from '../protocol/Preview';

interface PreviewAction { type: string; text?: string; delta?: number; url?: string; }
interface PreviewWheel { type: string; x: number; y: number; deltaX: number; deltaY: number; modifiers: number; }
interface PreviewAdjustmentResult { viewport?: PreviewViewport; viewportTolerance?: number; zoomFactor?: number; }

@Component
export struct PreviewPanel {
  @StorageLink('t3Foreground') @Watch('foregroundChanged') foreground: boolean = true;
  @Prop initialTabId: string = '';
  @Prop initialUrl: string = '';
  @Prop autoConnect: boolean = false;
  createTab: (url: string) => Promise<string> = async () => { throw new Error('预览创建尚未接入'); };
  listTabs: () => Promise<PreviewTab[]> = async () => { throw new Error('预览列表尚未接入'); };
  watchTabs: (changed: () => void) => (() => void) = () => (): void => {};
  resizeTab: (tabId: string, viewport: PreviewResizeViewport) => Promise<PreviewViewport> =
    async () => { throw new Error('预览尺寸切换尚未接入'); };
  zoomTab: (tabId: string, zoomFactor: number, currentViewport: PreviewViewport, stillControlled?: () => boolean) => Promise<PreviewZoomResult> =
    async () => { throw new Error('预览缩放尚未接入'); };
  requiresZoomRepair: () => boolean = () => false;
  closeTab: (tabId: string) => Promise<void> = async () => { throw new Error('预览关闭尚未接入'); };
  streamUrl: (tabId: string) => Promise<string> = async () => { throw new Error('媒体访问尚未接入'); };
  prepareConnection: () => void = () => {};
  isCurrent: () => boolean = () => false;
  onTab: (tabId: string) => void = () => {};
  onBack: () => void = () => {};
  @State frame: image.PixelMap | undefined = undefined;
  @State status: string = '选择已有页面后连接，或输入地址后前往';
  @State controller: string = '';
  private controlStatus(): string {
    if (!this.controller) return '';
    if (!this.canOperate) return '只读观看';
    if (this.controller === 'you') return '你正在控制';
    if (this.controller === 'agent') return 'Agent 正在控制';
    if (this.controller === 'another-viewer') return '另一查看器正在控制';
    return '等待取得控制权';
  }
  @State error: string = '';
  @State address: string = '';
  @State input: string = '';
  @State busy: boolean = false;
  @State canOperate: boolean = false;
  @State controlling: boolean = false;
  @State controlRevision: number = 0;
  @State repairTabs: string[] = [];
  @State frameCount: number = 0;
  @State waitingForFrame: boolean = false;
  @State firstFrameTimedOut: boolean = false;
  @State frameSkipped: boolean = false;
  @State tabId: string = '';
  @State tabs: PreviewTab[] = [];
  @State resizeChoice: number = 0;
  @State viewportLabel: string = '';
  @State toolsOpen: boolean = false;
  private stopWatching: (() => void) | undefined = undefined;
  private listing: boolean = false;
  private listAgain: boolean = false;
  private addressEditing: boolean = false;
  private addressDirty: boolean = false;
  private stream: PreviewStream | undefined = undefined;
  private firstFrameTimer: number = 0;
  private firstFrameRetryTimer: number = 0;
  private retiredFrame: image.PixelMap | undefined = undefined;
  private viewport: PreviewViewport = { width: 0, height: 0 };
  private generation: number = 0;
  private serverControlGeneration: number = -1;
  private displayWidth: number = 1;
  private displayHeight: number = 1;
  private touchX: number = 0;
  private touchY: number = 0;
  private hasTouch: boolean = false;
  private viewportPending: boolean = true;
  private viewportTolerance: number = 0;
  @State expectedViewport: PreviewViewport | undefined = undefined;
  @State pendingAdjustment: string = '';

  aboutToAppear(): void {
    this.tabId = this.initialTabId;
    this.address = this.initialUrl;
    if (this.autoConnect && this.tabId && this.foreground) {
      void this.connect();
    } else {
      void this.refreshTabs();
    }
  }
  private foregroundChanged(): void {
    if (this.foreground) return;
    this.disconnect();
    this.status = '应用进入后台，画面已断开；返回后请手动连接';
  }
  aboutToDisappear(): void { this.disconnect(); }
  private cancelFirstFrameRetry(): void {
    if (this.firstFrameRetryTimer) clearTimeout(this.firstFrameRetryTimer);
    this.firstFrameRetryTimer = 0;
  }
  private finishFirstFrameWait(): void {
    this.cancelFirstFrameRetry();
    if (this.firstFrameTimer) clearTimeout(this.firstFrameTimer);
    this.firstFrameTimer = 0; this.waitingForFrame = false; this.firstFrameTimedOut = false;
  }
  private disconnect(keepFrame: boolean = false): void {
    this.generation++; this.busy = false;
    this.finishFirstFrameWait();
    this.stopWatching?.(); this.stopWatching = undefined; this.listing = false; this.listAgain = false;
    this.stream?.stop(); this.stream = undefined;
    this.canOperate = false; this.controlling = false; this.serverControlGeneration = -1; this.hasTouch = false;
    this.controller = '';
    this.viewportPending = true; this.viewport = { width: 0, height: 0 };
    this.expectedViewport = undefined; this.pendingAdjustment = ''; this.viewportLabel = '';
    if (!keepFrame) {
      if (this.frame) void this.frame.release().catch(() => {});
      this.frame = undefined; this.frameSkipped = false;
    }
    if (this.retiredFrame) void this.retiredFrame.release().catch(() => {});
    this.retiredFrame = undefined;
  }
  private async connect(expectedViewport?: PreviewViewport, adjustment: string = '', tolerance: number = 0,
    recoveringTabId: string = ''): Promise<void> {
    if (this.busy || !this.foreground) return;
    if (recoveringTabId && (recoveringTabId !== this.tabId || !this.isCurrent())) return;
    this.disconnect(this.frameSkipped); this.busy = true; this.error = ''; this.frameCount = 0;
    this.expectedViewport = expectedViewport;
    this.viewportTolerance = tolerance;
    this.pendingAdjustment = adjustment;
    const generation = this.generation;
    let createdTabId = '';
    try {
      if (!recoveringTabId) this.prepareConnection();
      if (!this.isCurrent()) throw new Error('环境或会话已改变，请重新打开预览');
      if (!this.tabId) {
        previewNavigation(this.address);
        const submittedAddress = this.address.trim();
        const tabId = await this.createTab(submittedAddress);
        if (generation !== this.generation || !this.foreground || !this.isCurrent()) return;
        createdTabId = tabId;
        this.tabId = tabId; this.onTab(tabId);
        if (this.address.trim() === submittedAddress) { this.addressDirty = false; this.addressEditing = false; }
        this.tabs = this.tabs.concat([{ tabId, url: submittedAddress, title: submittedAddress }]);
      }
      const target = await this.streamUrl(this.tabId);
      if (generation !== this.generation || !this.foreground || !this.isCurrent()) return;
      const stream = new PreviewStream((): boolean => generation === this.generation && this.foreground && this.isCurrent());
      this.stream = stream;
      this.waitingForFrame = true;
      this.firstFrameTimer = setTimeout(() => {
        this.firstFrameTimer = 0;
        if (generation === this.generation && this.waitingForFrame) {
          this.firstFrameTimedOut = true;
          if (this.repairBlocked()) {
            this.pendingAdjustment = ''; this.expectedViewport = undefined;
          }
        }
      }, 12000) as number;
      if (createdTabId) {
        this.firstFrameRetryTimer = setTimeout(() => {
          this.firstFrameRetryTimer = 0;
          if (generation !== this.generation || this.tabId !== createdTabId ||
            !this.foreground || !this.isCurrent() || !this.waitingForFrame || this.stream !== stream) return;
          this.busy = false;
          void this.connect(undefined, '', 0, createdTabId);
        }, 3500) as number;
      }
      stream.onFrame = (frame: image.PixelMap, size: PreviewViewport): void => {
        const expected = this.expectedViewport;
        const matchesViewport = this.viewport.width > 0 && previewFrameMatchesViewport(size, this.viewport);
        if (generation !== this.generation || !this.foreground || !this.isCurrent() ||
          !this.hasExpectedViewport() || ((this.pendingAdjustment || this.frameSkipped) && !matchesViewport)) {
          void frame.release().catch(() => {});
          return;
        }
        if (expected && this.repairBlocked()) this.repairTabs = this.repairTabs.filter((tabId: string) => tabId !== this.tabId);
        this.expectedViewport = undefined; this.pendingAdjustment = '';
        this.frameSkipped = false;
        if (this.waitingForFrame) this.finishFirstFrameWait();
        if (matchesViewport) this.viewportLabel = this.viewport.width + ' × ' + this.viewport.height;
        else this.viewportLabel = '触控坐标待同步';
        if (this.retiredFrame) void this.retiredFrame.release().catch(() => {});
        this.retiredFrame = this.frame; this.frame = frame; this.frameCount++;
        this.viewportPending = !matchesViewport;
        if (!matchesViewport) this.hasTouch = false;
        this.status = '实时画面';
      };
      stream.onFrameSkipped = (): void => {
        if (generation !== this.generation || !this.foreground || !this.isCurrent()) return;
        this.frameSkipped = true; this.viewportPending = true; this.hasTouch = false;
        this.viewportLabel = '';
      };
      stream.onViewport = (viewport: PreviewViewport): void => {
        if (generation !== this.generation) return;
        this.viewport = viewport; this.hasTouch = false; this.viewportPending = true; this.viewportLabel = '';
      };
      stream.onControl = (control: PreviewControl): void => {
        if (generation !== this.generation) return;
        if (control.controller === 'agent' || control.controller === 'another-viewer') this.cancelFirstFrameRetry();
        if (this.serverControlGeneration !== control.generation || this.canOperate !== control.canOperate ||
          this.controlling !== (control.controller === 'you')) {
          this.controlRevision++;
          this.hasTouch = false;
        }
        this.canOperate = control.canOperate; this.controlling = control.controller === 'you';
        this.serverControlGeneration = control.generation;
        this.controller = control.controller;
        if (control.dialog) this.error = '远端网页有对话框待处理，请在桌面端处理';
      };
      stream.onStatus = (status: string): void => { if (generation !== this.generation) return; this.status = status; };
      stream.onFailure = (message: string): void => {
        if (generation !== this.generation) return;
        this.finishFirstFrameWait();
        this.pendingAdjustment = ''; this.error = message; this.canOperate = false; this.controlling = false; this.status = '画面已停止';
        this.controller = ''; this.hasTouch = false;
      };
      await stream.start(target);
      if (generation === this.generation && this.foreground && this.isCurrent()) void this.refreshTabs();
    } catch (reason) {
      if (generation === this.generation) {
        this.finishFirstFrameWait();
        this.pendingAdjustment = ''; this.error = (reason as Error).message;
      }
    }
    finally { if (generation === this.generation) this.busy = false; }
  }
  private syncAddress(): void {
    const selected = this.tabs.find((tab: PreviewTab): boolean => tab.tabId === this.tabId);
    if (selected && !this.addressDirty) this.address = selected.url;
  }
  private async refreshTabs(): Promise<void> {
    if (!this.foreground) return;
    if (this.listing) { this.listAgain = true; return; }
    this.listing = true;
    const generation = this.generation;
    try {
      this.prepareConnection();
      if (!this.isCurrent()) throw new Error('环境或会话已改变，请重新打开预览');
      if (!this.stopWatching) this.stopWatching = this.watchTabs((): void => {
        if (generation === this.generation && this.foreground && this.isCurrent()) void this.refreshTabs();
      });
      const tabs = await this.listTabs();
      if (generation !== this.generation || !this.foreground || !this.isCurrent()) return;
      // An event received during the read invalidates that snapshot; read again before publishing.
      if (this.listAgain) return;
      this.tabs = tabs; this.syncAddress();
      if (this.tabId && !tabs.some((tab: PreviewTab): boolean => tab.tabId === this.tabId)) {
        this.disconnect(); this.tabId = ''; this.onTab(''); this.frameCount = 0;
        this.status = '原页面已关闭，请选择其他页面或新建';
      }
    } catch (reason) { if (generation === this.generation) this.error = (reason as Error).message; }
    finally {
      if (generation === this.generation) {
        this.listing = false;
        if (this.listAgain) { this.listAgain = false; void this.refreshTabs(); }
      }
    }
  }
  private selectTab(tabId: string): void {
    if (this.busy || !this.foreground || !this.isCurrent() || tabId === this.tabId) return;
    const tab = this.tabs.find((item: PreviewTab): boolean => item.tabId === tabId);
    if (!tab) return;
    this.disconnect(); this.tabId = tab.tabId; this.address = tab.url; this.input = '';
    this.addressDirty = false; this.addressEditing = false;
    this.frameCount = 0; this.error = ''; this.onTab(tab.tabId);
    this.status = '已选择页面，点击连接查看';
  }
  private newTab(): void {
    if (this.busy || !this.foreground || !this.isCurrent()) return;
    this.disconnect(); this.tabId = ''; this.address = ''; this.input = '';
    this.addressDirty = false; this.addressEditing = false;
    this.frameCount = 0; this.error = ''; this.onTab('');
    this.status = '输入地址后点击前往，将新建远端页面';
  }
  private confirmCloseTab(): void {
    if (!this.tabId || this.busy) return;
    this.cancelFirstFrameRetry();
    const tabId = this.tabId;
    AlertDialog.show({ title: '关闭远端页面？', message: '将关闭此浏览器标签页，未提交的网页内容可能丢失。返回只会断开画面连接。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '关闭页面', action: () => { void this.closeConfirmed(tabId); } } });
  }
  private async closeConfirmed(tabId: string): Promise<void> {
    if (this.busy || tabId !== this.tabId || !this.isCurrent()) return;
    const generation = this.generation;
    this.busy = true; this.error = '';
    try {
      await this.closeTab(tabId);
      if (generation !== this.generation || tabId !== this.tabId || !this.isCurrent()) return;
      this.disconnect(); this.tabs = this.tabs.filter((tab: PreviewTab): boolean => tab.tabId !== tabId);
      this.repairTabs = this.repairTabs.filter((id: string) => id !== tabId);
      this.tabId = ''; this.onTab(''); this.frameCount = 0;
      this.status = '远端页面已关闭'; this.error = '';
    } catch (reason) {
      if (generation === this.generation) this.error = (reason as Error).message + '。关闭结果未确认，不会自动重试，请核对远端页面。';
    } finally { this.busy = false; }
  }
  private canResize(): boolean {
    return this.canAdjustViewport() && this.controlling;
  }
  private canAdjustViewport(): boolean {
    return this.foreground && !this.busy && (!this.pendingAdjustment || this.frameSkipped) && this.canOperate && !!this.tabId && this.isCurrent();
  }
  private hasExpectedViewport(): boolean {
    const expected = this.expectedViewport;
    return !expected || (Math.abs(this.viewport.width - expected.width) <= this.viewportTolerance &&
      Math.abs(this.viewport.height - expected.height) <= this.viewportTolerance);
  }
  private canZoom(): boolean {
    const tab = this.tabs.find((item: PreviewTab): boolean => item.tabId === this.tabId);
    return !this.repairBlocked() && this.canAdjustViewport() && !!tab?.viewport && tab?.zoomFactor !== undefined &&
      (this.frameSkipped ? (tab.viewport.width !== undefined && tab.viewport.height !== undefined) ||
        (this.viewport.width > 0 && this.hasExpectedViewport()) : !!this.frame && !this.viewportPending && this.viewport.width > 0);
  }
  private repairBlocked(): boolean { return this.repairTabs.includes(this.tabId); }
  private canRepairZoom(): boolean {
    const viewport = this.tabs.find((tab: PreviewTab): boolean => tab.tabId === this.tabId)?.viewport;
    return this.canZoom() && this.controlling && (viewport?._tag === 'freeform' || viewport?._tag === 'preset') &&
      viewport.width !== undefined && viewport.height !== undefined;
  }
  private zoomMenu(tabId: string, generation: number, controlRevision: number): MenuElement[] {
    return PREVIEW_ZOOM_LEVELS.map((factor: number): MenuElement => ({
      value: factor === DEFAULT_PREVIEW_ZOOM_FACTOR ? '100%（恢复）' : Math.round(factor * 100) + '%',
      action: () => {
        if (tabId !== this.tabId || generation !== this.generation || controlRevision !== this.controlRevision) return;
        if (factor === DEFAULT_PREVIEW_ZOOM_FACTOR && this.requiresZoomRepair()) this.confirmZoomRepair();
        else void this.applyZoom(factor);
      }
    }));
  }
  private confirmZoomRepair(): void {
    if (!this.canRepairZoom()) {
      this.error = '恢复 100% 需要控制权和固定页面尺寸。';
      return;
    }
    const tabId = this.tabId;
    const generation = this.generation;
    const controlRevision = this.controlRevision;
    const stillControlled = (): boolean => this.foreground && this.isCurrent() && this.tabId === tabId &&
      this.generation === generation && this.controlRevision === controlRevision && this.canOperate && this.controlling;
    AlertDialog.show({
      title: '恢复此页面的 100% 缩放？',
      message: '当前服务需要将页面尺寸临时调整一像素再还原，页面可能短暂重新排版。网址不会刷新。若中断，请选择一个不同的固定尺寸并应用。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '恢复 100%', action: () => {
        if (stillControlled() && this.canRepairZoom() && this.requiresZoomRepair()) {
          void this.applyZoom(DEFAULT_PREVIEW_ZOOM_FACTOR, stillControlled);
        }
      } }
    });
  }
  private zoomLabel(): string {
    const zoom = this.tabs.find((tab: PreviewTab): boolean => tab.tabId === this.tabId)?.zoomFactor;
    return zoom === undefined ? '页面缩放' : '缩放 ' + Math.round(zoom * 100) + '%';
  }
  private async applyResize(): Promise<void> {
    const option = PREVIEW_RESIZE_CHOICES[this.resizeChoice];
    if (!option || !this.canResize()) return;
    if (this.repairBlocked()) {
      const viewport = this.tabs.find((tab: PreviewTab): boolean => tab.tabId === this.tabId)?.viewport;
      if (viewport?.width === option.viewport.width && viewport?.height === option.viewport.height) {
        this.error = '请选择一个不同的固定尺寸并应用。';
        return;
      }
    }
    await this.adjustViewport(async (tabId: string): Promise<PreviewAdjustmentResult> =>
      ({ viewport: await this.resizeTab(tabId, option.viewport) }), '尺寸切换');
  }
  private async applyZoom(zoomFactor: number, stillControlled?: () => boolean): Promise<void> {
    if (!this.canZoom() || !PREVIEW_ZOOM_LEVELS.includes(zoomFactor)) return;
    if (zoomFactor === DEFAULT_PREVIEW_ZOOM_FACTOR && this.requiresZoomRepair() &&
      (!stillControlled || !stillControlled() || !this.canRepairZoom())) return;
    const viewport = this.viewport;
    await this.adjustViewport((tabId: string): Promise<PreviewZoomResult> =>
      this.zoomTab(tabId, zoomFactor, viewport, stillControlled), stillControlled ? '恢复 100%' : '缩放', true, !!stillControlled);
  }
  private async adjustViewport(update: (tabId: string) => Promise<PreviewAdjustmentResult>,
    adjustment: string, changesZoom: boolean = false, repairsZoom: boolean = false): Promise<void> {
    const tabId = this.tabId;
    if (repairsZoom) this.repairTabs = this.repairTabs.concat([tabId]);
    this.cancelFirstFrameRetry();
    const generation = this.generation;
    this.busy = true; this.hasTouch = false; this.viewportPending = true; this.viewportLabel = ''; this.error = '';
    try {
      const result = await update(tabId);
      if (generation !== this.generation || tabId !== this.tabId || !this.foreground || !this.isCurrent()) return;
      if (changesZoom) this.updateTabZoom(tabId, result.zoomFactor);
      this.busy = false;
      await this.connect(result.viewport, adjustment, result.viewportTolerance);
    } catch (_) {
      if (generation === this.generation && tabId === this.tabId) {
        if (!this.repairBlocked()) this.disconnect(this.frameSkipped);
        if (changesZoom) this.updateTabZoom(tabId, undefined);
        this.error = this.repairBlocked() ? '恢复未确认，请选择不同的固定尺寸并应用。' : adjustment + '未确认，请重新连接核对';
      }
    } finally {
      if (generation === this.generation) this.busy = false;
    }
  }
  private updateTabZoom(tabId: string, zoomFactor: number | undefined): void {
    this.tabs = this.tabs.map((tab: PreviewTab): PreviewTab =>
      tab.tabId === tabId ? { tabId: tab.tabId, url: tab.url, title: tab.title, viewport: tab.viewport, zoomFactor } : tab);
  }
  private inputSuspended(): boolean { return !!this.pendingAdjustment || this.frameSkipped || this.repairBlocked(); }
  private async send(input: PreviewAction): Promise<void> {
    const stream = this.stream;
    if (!stream || this.busy || this.pendingAdjustment ||
      (this.inputSuspended() && input.type !== 'takeControl' && input.type !== 'releaseControl')) return;
    this.cancelFirstFrameRetry();
    this.busy = true; this.error = '';
    try { await stream.send(input); }
    catch (reason) { this.error = (reason as Error).message; }
    finally { this.busy = false; }
  }
  private async sendKey(key: string): Promise<void> {
    const stream = this.stream;
    if (!stream || this.busy || this.inputSuspended()) return;
    const generation = this.generation; const revision = this.controlRevision;
    if (!this.hasInputLease(stream, generation, revision)) return;
    this.cancelFirstFrameRetry();
    this.busy = true; this.error = '';
    try {
      await stream.send(previewKey(key, true));
      if (this.hasInputLease(stream, generation, revision)) await stream.send(previewKey(key, false));
    } catch (reason) { if (generation === this.generation) this.error = (reason as Error).message; }
    finally { if (generation === this.generation) this.busy = false; }
  }
  private hasInputLease(stream: PreviewStream, generation: number, revision: number): boolean {
    return this.foreground && this.isCurrent() && this.stream === stream && this.generation === generation &&
      this.controlRevision === revision && this.canOperate && this.controlling;
  }
  private async touch(event: TouchEvent): Promise<void> {
    const stream = this.stream;
    const generation = this.generation; const revision = this.controlRevision;
    if (!stream || !this.hasInputLease(stream, generation, revision) || this.busy || this.inputSuspended() ||
      !this.frame || this.viewportPending || this.viewport.width <= 0) return;
    if (event.type === TouchType.Down && event.touches.length === 1) {
      this.touchX = event.touches[0].x; this.touchY = event.touches[0].y; this.hasTouch = true; return;
    }
    if (event.type === TouchType.Cancel || event.touches.length > 1) { this.hasTouch = false; return; }
    if (event.type !== TouchType.Up || !this.hasTouch || !event.changedTouches.length) return;
    this.hasTouch = false;
    const x = event.changedTouches[0].x; const y = event.changedTouches[0].y;
    const point = previewPoint(this.touchX, this.touchY, this.displayWidth, this.displayHeight, this.viewport);
    if (!point) return;
    this.busy = true; this.error = '';
    try {
      if (Math.abs(x - this.touchX) + Math.abs(y - this.touchY) > 8) {
        const scale = Math.min(this.displayWidth / this.viewport.width, this.displayHeight / this.viewport.height);
        const wheel: PreviewWheel = { type: 'wheel', x: point.x, y: point.y,
          deltaX: (this.touchX - x) / scale, deltaY: (this.touchY - y) / scale, modifiers: 0 };
        await stream.send(wheel);
      } else {
        await stream.send(previewMouse(point, true));
        if (this.hasInputLease(stream, generation, revision)) await stream.send(previewMouse(point, false));
      }
    } catch (reason) { if (generation === this.generation) this.error = (reason as Error).message; }
    finally { if (generation === this.generation) this.busy = false; }
  }
  private async typeText(): Promise<void> {
    if (this.inputSuspended()) return;
    if (!this.input || this.input.length > 4096) { this.error = '文字需要在 1–4096 字符之间'; return; }
    const value = this.input; this.input = '';
    await this.send({ type: 'text', text: value });
  }
  private navigate(): void {
    if (!this.canNavigate()) return;
    try {
      previewNavigation(this.address);
      if (!this.tabId) { void this.connect(); return; }
      if (!this.stream) return;
      this.addressDirty = false; this.addressEditing = false;
      void this.send({ type: 'navigate', url: this.address.trim() });
    }
    catch (reason) { this.error = (reason as Error).message; }
  }
  private canNavigate(): boolean {
    return this.foreground && !this.busy && !this.inputSuspended() &&
      (this.tabId ? this.controlling : !!this.address.trim());
  }
  build() {
    Column() {
      TopBar({
        title: '浏览器预览',
        showBack: true,
        onBack: () => { this.cancelFirstFrameRetry(); this.onBack(); }
      }) {
        AppButton({
          label: this.waitingForFrame || this.frame || this.error ? '重新连接' : '连接',
          kind: 'primary',
          compact: true,
          disabled: !(this.foreground && !this.busy && !!this.tabId),
          onTap: () => { void this.connect(); }
        })
      }

      Column({ space: Space.xs }) {
        Row({ space: Space.xs }) {
          Select(this.tabs.map((tab: PreviewTab): SelectOption => ({ value: tab.title })))
            .value(this.tabs.find((tab: PreviewTab): boolean => tab.tabId === this.tabId)?.title || '选择页面')
            .layoutWeight(1).constraintSize({ minHeight: 40 }).enabled(!this.busy && this.foreground && this.tabs.length > 0)
            .onSelect((index: number) => { if (this.tabs[index]) this.selectTab(this.tabs[index].tabId); })
          Button('更多', { type: ButtonType.Normal }).constraintSize({ minWidth: 56, minHeight: 40 })
            .padding({ left: Space.sm, right: Space.sm })
            .fontSize(FontSize.callout).fontWeight(Weight.medium).borderRadius(Radius.button)
            .backgroundColor($r('app.color.card')).fontColor($r('app.color.ink')).accessibilityText('更多页面操作')
            .bindMenu([
              { value: '更新标签列表', enabled: !this.busy && this.foreground, action: () => { void this.refreshTabs(); } },
              { value: '新建标签', enabled: !this.busy && this.foreground, action: () => this.newTab() },
              { value: '关闭远端页面', enabled: !!this.tabId && !this.busy, action: () => this.confirmCloseTab() }
            ])
        }.width('100%').alignItems(VerticalAlign.Center)

        Row({ space: Space.xs }) {
          TextInput({ placeholder: '远端网页地址，例如 http://localhost:3000', text: this.address })
            .layoutWeight(1).constraintSize({ minHeight: 40 })
            .fontSize(FontSize.body).fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
            .backgroundColor(Color.Transparent).padding({ left: Space.xs, right: Space.xxs })
            .onChange((value: string) => { if (value !== this.address) { this.address = value; this.addressDirty = true; } })
            .onFocus(() => { this.addressEditing = true; })
            .onBlur(() => { this.addressEditing = false; this.syncAddress(); })
          AppButton({
            label: '前往',
            kind: 'secondary',
            compact: true,
            disabled: !this.canNavigate(),
            onTap: () => this.navigate()
          })
        }
        .width('100%')
        .padding({ left: Space.xs, right: 6, top: Space.xxs, bottom: Space.xxs })
        .backgroundColor($r('app.color.card'))
        .borderRadius(Radius.card)
        .alignItems(VerticalAlign.Center)

        Text((this.pendingAdjustment ? '等待' + this.pendingAdjustment + '后的画面' : this.status) +
          (this.controller ? ' · ' + this.controlStatus() : '') +
          (this.viewportLabel ? ' · ' + this.viewportLabel : '') + (this.frameCount ? ' · ' + this.frameCount + ' 帧' : ''))
          .fontSize(FontSize.caption).lineHeight(LineHeight.caption)
          .fontColor($r('app.color.muted')).width('100%')
        if (this.error) {
          Text(this.error).fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.danger')).width('100%')
        }
        if (this.frameSkipped) {
          Text((this.frame ? '已跳过超限画面，当前显示上一帧。' : '已跳过超限画面。') +
            (this.canZoom() ? '可换一个缩放比例。' : '等待可用画面。'))
            .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted')).width('100%')
        }
        if (this.repairBlocked() && !this.busy && !this.pendingAdjustment && !this.error) {
          Text('恢复未确认，请选择不同的固定尺寸并应用。')
            .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.danger')).width('100%')
        }
        Stack() {
          if (this.frame) Image(this.frame).objectFit(ImageFit.Contain).width('100%').height('100%')
          else Text(this.firstFrameTimedOut ? '暂未收到可显示的画面，请点击重新连接' :
            this.waitingForFrame ? '正在等待远端页面的首帧…' :
            this.tabId ? '连接后显示所选页面' : '输入地址并前往，打开远端页面')
            .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.muted')).padding(Space.lg)
        }.width('100%').layoutWeight(1).backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
          .onAreaChange((_, area: Area) => { this.displayWidth = Number(area.width); this.displayHeight = Number(area.height); })
          .onTouch((event: TouchEvent) => { void this.touch(event); })
        Flex({ wrap: FlexWrap.Wrap }) {
          Button(this.controller === 'another-viewer' ? '等待释放' : this.controlling ? '释放控制' : '取得控制')
            .constraintSize({ minWidth: Sizes.iconHit, minHeight: 40 }).flexGrow(1).fontSize(FontSize.callout).borderRadius(Radius.button)
            .margin({ right: 6, bottom: Space.xxs })
            .backgroundColor($r('app.color.card')).fontColor($r('app.color.ink'))
            .enabled(this.canOperate && this.controller !== 'another-viewer' && !this.busy && !this.pendingAdjustment)
            .onClick(() => { void this.send({ type: this.controlling ? 'releaseControl' : 'takeControl' }); })
          Button('后退').constraintSize({ minWidth: Sizes.iconHit, minHeight: 40 }).flexGrow(1).fontSize(FontSize.callout).borderRadius(Radius.button)
            .backgroundColor($r('app.color.card')).fontColor($r('app.color.ink'))
            .margin({ right: 6, bottom: Space.xxs })
            .enabled(this.controlling && !this.busy && !this.inputSuspended()).onClick(() => { void this.send(previewHistory(-1) as PreviewAction); })
          Button('前进').constraintSize({ minWidth: Sizes.iconHit, minHeight: 40 }).flexGrow(1).fontSize(FontSize.callout).borderRadius(Radius.button)
            .backgroundColor($r('app.color.card')).fontColor($r('app.color.ink'))
            .margin({ right: 6, bottom: Space.xxs })
            .enabled(this.controlling && !this.busy && !this.inputSuspended()).onClick(() => { void this.send(previewHistory(1) as PreviewAction); })
          Button('刷新').constraintSize({ minWidth: Sizes.iconHit, minHeight: 40 }).flexGrow(1).fontSize(FontSize.callout).borderRadius(Radius.button)
            .backgroundColor($r('app.color.card')).fontColor($r('app.color.ink'))
            .margin({ bottom: Space.xxs })
            .enabled(this.controlling && !this.busy && !this.inputSuspended()).onClick(() => { void this.send({ type: 'reload' }); })
        }.width('100%')
        Button(this.toolsOpen ? '收起工具' : '工具 · 尺寸、缩放与文字输入', { type: ButtonType.Normal }).width('100%')
          .constraintSize({ minHeight: 40 }).fontSize(FontSize.callout).fontWeight(Weight.medium).borderRadius(Radius.button)
          .backgroundColor($r('app.color.card')).fontColor($r('app.color.ink'))
          .onClick(() => { this.toolsOpen = !this.toolsOpen; })
        if (this.toolsOpen) {
          Scroll() {
            Column({ space: Space.xs }) {
              Column({ space: Space.xs }) {
                Select(PREVIEW_RESIZE_CHOICES.map((choice: PreviewResizeChoice): SelectOption => ({ value: choice.label })))
                  .selected(this.resizeChoice).value(PREVIEW_RESIZE_CHOICES[this.resizeChoice].label)
                  .width('100%').constraintSize({ minHeight: 42 }).enabled(this.canResize()).accessibilityText('浏览器尺寸')
                  .onSelect((index: number) => { if (PREVIEW_RESIZE_CHOICES[index]) this.resizeChoice = index; })
                Flex({ wrap: FlexWrap.Wrap }) {
                  Button('应用尺寸', { type: ButtonType.Normal }).flexGrow(1).constraintSize({ minWidth: Sizes.iconHit, minHeight: 40 })
                    .fontSize(FontSize.callout).borderRadius(Radius.button).margin({ right: 6 })
                    .backgroundColor($r('app.color.group')).fontColor($r('app.color.ink')).enabled(this.canResize())
                    .onClick(() => { void this.applyResize(); })
                  Button(this.zoomLabel(), { type: ButtonType.Normal }).flexGrow(1).constraintSize({ minWidth: Sizes.iconHit, minHeight: 40 })
                    .fontSize(FontSize.callout).borderRadius(Radius.button)
                    .backgroundColor($r('app.color.group')).fontColor($r('app.color.ink')).enabled(this.canZoom())
                    .bindMenu(this.zoomMenu(this.tabId, this.generation, this.controlRevision))
                }.width('100%')
              }.width('100%')
              TextInput({ placeholder: '点选网页输入框后输入文字', text: this.input }).width('100%')
                .fontSize(FontSize.body).fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
                .backgroundColor($r('app.color.group')).borderRadius(Radius.button).padding({ left: Space.sm, right: Space.sm })
                .constraintSize({ minHeight: 40 }).onChange((value: string) => { this.input = value; })
              Row({ space: Space.xs }) {
                Row() {
                  AppButton({
                    label: '输入文字',
                    kind: 'primary',
                    compact: true,
                    fill: true,
                    disabled: !(this.controlling && !this.busy && !this.inputSuspended()),
                    onTap: () => { void this.typeText(); }
                  })
                }.layoutWeight(1)
                Row() {
                  AppButton({
                    label: '回车',
                    kind: 'secondary',
                    compact: true,
                    fill: true,
                    disabled: !(this.controlling && !this.busy && !this.inputSuspended()),
                    onTap: () => { void this.sendKey('Enter'); }
                  })
                }.layoutWeight(1)
              }.width('100%')
            }.width('100%').padding(Space.sm).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
          }.width('100%').constraintSize({ maxHeight: 190 })
        }
      }.layoutWeight(1).width('100%').padding({ left: Space.page, right: Space.page, top: Space.xxs, bottom: Space.md })
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
