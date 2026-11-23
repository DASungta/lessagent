import { webview } from '@kit.ArkWeb';
import {
  harmonyHtmlRenderTheme,
  HtmlRenderEntry,
  htmlRenderFallbackCssScript,
  htmlRenderFrameHeight,
  htmlRenderThemeFragment,
  htmlRenderThemeMessageJson,
  readHtmlRenderOverflow,
  shouldAllowHtmlRenderNavigation,
  stripUrlFragment
} from '../protocol/HtmlRender';
import { currentAppearance } from '../services/Appearance';
import { T3Client } from '../services/T3Client';
import { FontSize, Radius, Sizes, Space } from '../common/Theme';

const OVERFLOW_PROBE_JS = '(function(){' +
  'var d=document.documentElement,b=document.body;' +
  'var sw=Math.max(d?d.scrollWidth:0,b?b.scrollWidth:0);' +
  'var sh=Math.max(d?d.scrollHeight:0,b?b.scrollHeight:0);' +
  'var bottom=0;' +
  'if(b){' +
  'var bs=getComputedStyle(b);' +
  'var padB=parseFloat(bs.paddingBottom)||0;' +
  'var marB=parseFloat(bs.marginBottom)||0;' +
  'var kids=b.children;' +
  'for(var i=0;i<kids.length;i++){' +
  'var el=kids[i];var cs=getComputedStyle(el);' +
  'if(cs.display==="none"||cs.visibility==="hidden")continue;' +
  'var r=el.getBoundingClientRect();' +
  'if(r.height>0||r.width>0){' +
  'var mb=parseFloat(cs.marginBottom)||0;' +
  'bottom=Math.max(bottom,r.bottom+window.scrollY+mb);' +
  '}' +
  '}' +
  'if(bottom>0)bottom=Math.ceil(bottom+padB+marB+12);' +
  '}' +
  'var h=bottom>0?Math.max(bottom,sh>window.innerHeight+2?sh:0):sh;' +
  'return JSON.stringify({x:sw>window.innerWidth+1,y:h>20000,height:h});})()';

@Component
export struct HtmlRenderWebView {
  @Prop @Watch('onUriChange') uri: string = '';
  @Prop title: string = 'HTML';
  @Prop nested: boolean = true;
  @Prop isHtmlRender: boolean = true;
  @StorageProp('t3SystemColorMode') @Watch('onDarkModeChange') systemColorMode: number = -1;
  @StorageProp('t3AppearanceMode') @Watch('onDarkModeChange') appearanceMode: string = '';
  onOpenExternalLink: (url: string) => void = () => {};
  onLoadError: () => void = () => {};
  onMeasuredContent: (height: number, overflowY: boolean) => void = () => {};

  private controller: webview.WebviewController = new webview.WebviewController();
  private crashes: number = 0;
  private controllerAttached: boolean = false;
  private initialLoadedUrl: string = '';
  private appliedDarkMode: boolean = false;
  private probeTimer: number = 0;
  private alive: boolean = false;
  @State loaded: boolean = false;
  @State overflowY: boolean = false;
  @State renderKey: number = 0;

  private isDarkTheme(): boolean {
    const mode = this.appearanceMode || currentAppearance;
    if (mode === 'dark') return true;
    if (mode === 'light') return false;
    return this.systemColorMode === 0;
  }

  aboutToAppear(): void {
    this.alive = true;
    this.appliedDarkMode = this.isDarkTheme();
    this.initialLoadedUrl = this.buildLoadUrl();
  }

  aboutToDisappear(): void {
    this.alive = false;
    if (this.probeTimer) {
      clearTimeout(this.probeTimer);
      this.probeTimer = 0;
    }
  }

  private buildLoadUrl(): string {
    if (!this.uri) return '';
    if (!this.isHtmlRender) return this.uri;
    return this.uri + htmlRenderThemeFragment(harmonyHtmlRenderTheme(this.isDarkTheme()));
  }

  private onUriChange(): void {
    this.crashes = 0;
    this.loaded = false;
    this.overflowY = false;
    this.appliedDarkMode = this.isDarkTheme();
    this.initialLoadedUrl = this.buildLoadUrl();
    if (this.controllerAttached && this.initialLoadedUrl) {
      try {
        this.controller.loadUrl(this.initialLoadedUrl);
      } catch (_) {}
    }
  }

  private onDarkModeChange(): void {
    if (!this.loaded || !this.controllerAttached) return;
    const dark = this.isDarkTheme();
    if (this.appliedDarkMode === dark) return;
    this.appliedDarkMode = dark;
    if (this.isHtmlRender) {
      this.pushThemeMessage(dark);
    } else {
      this.pushFallbackThemeCss(dark);
    }
  }

  private pushThemeMessage(dark: boolean): void {
    const theme = harmonyHtmlRenderTheme(dark);
    const script = 'window.postMessage(' + htmlRenderThemeMessageJson(theme) + ', "*");';
    try {
      void this.controller.runJavaScript(script).catch(() => {});
    } catch (_) {}
  }

  private pushFallbackThemeCss(dark: boolean): void {
    const theme = harmonyHtmlRenderTheme(dark);
    try {
      void this.controller.runJavaScript(htmlRenderFallbackCssScript(theme)).catch(() => {});
    } catch (_) {}
  }

  private scheduleProbe(delayMs: number): void {
    if (!this.nested || !this.alive) return;
    if (this.probeTimer) {
      clearTimeout(this.probeTimer);
      this.probeTimer = 0;
    }
    this.probeTimer = setTimeout(() => {
      this.probeTimer = 0;
      if (this.alive) this.probeOverflow();
    }, delayMs);
  }

  private probeOverflow(): void {
    if (!this.nested || !this.controllerAttached) return;
    try {
      void this.controller.runJavaScript(OVERFLOW_PROBE_JS).then((raw: string) => {
        if (!raw) return;
        let text = raw;
        if (text.startsWith('"') && text.endsWith('"')) {
          try {
            const unquoted: Object = JSON.parse(text) as Object;
            if (typeof unquoted === 'string') text = unquoted;
          } catch (_) {}
        }
        const parsed = readHtmlRenderOverflow(text);
        if (!parsed) return;
        this.overflowY = parsed.y;
        this.onMeasuredContent(parsed.contentHeight, parsed.y);
      }).catch(() => {});
    } catch (_) {}
  }

  private handleRenderCrash(): void {
    this.crashes += 1;
    if (this.crashes > 1) {
      this.onLoadError();
      return;
    }
    this.loaded = false;
    this.overflowY = false;
    this.controllerAttached = false;
    this.controller = new webview.WebviewController();
    this.initialLoadedUrl = this.buildLoadUrl();
    this.renderKey += 1;
  }

  private allowWorkspaceFileNavigation(reqUrl: string): boolean {
    if (!reqUrl || !this.uri) return false;
    if (stripUrlFragment(reqUrl) === stripUrlFragment(this.uri)) return true;
    const baseSlash = this.uri.indexOf('/', this.uri.indexOf('://') + 3);
    const reqSlash = reqUrl.indexOf('/', reqUrl.indexOf('://') + 3);
    if (baseSlash > 0 && reqSlash > 0 && this.uri.slice(0, baseSlash) === reqUrl.slice(0, reqSlash)) {
      return true;
    }
    return false;
  }

  private bgHex(): string {
    return this.isDarkTheme() ? '#0a0a0a' : '#fcfcfc';
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.initialLoadedUrl) {
        ForEach([this.renderKey], (_key: number) => {
          Web({ src: this.initialLoadedUrl, controller: this.controller })
            .width('100%')
            .height('100%')
            .backgroundColor(this.bgHex())
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(false)
            .geolocationAccess(false)
            .zoomAccess(!this.nested)
            .overviewModeAccess(!this.isHtmlRender)
            .multiWindowAccess(true)
            .nestedScroll({
              scrollForward: this.nested && !this.overflowY ? NestedScrollMode.PARENT_FIRST : NestedScrollMode.SELF_FIRST,
              scrollBackward: this.nested && !this.overflowY ? NestedScrollMode.PARENT_FIRST : NestedScrollMode.SELF_FIRST
            })
            .onControllerAttached(() => {
              this.controllerAttached = true;
            })
            .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
              const req = event.data;
              const reqUrl = req ? req.getRequestUrl() : '';
              const mainFrame = req ? req.isMainFrame() : true;
              if (this.isHtmlRender) {
                if (shouldAllowHtmlRenderNavigation(reqUrl, this.uri, mainFrame)) {
                  return false;
                }
                if (mainFrame && /^https?:\/\//i.test(reqUrl)) {
                  this.onOpenExternalLink(reqUrl);
                }
                return true;
              }
              if (!mainFrame || this.allowWorkspaceFileNavigation(reqUrl)) {
                return false;
              }
              if (/^https?:\/\//i.test(reqUrl)) {
                this.onOpenExternalLink(reqUrl);
              }
              return true;
            })
            .onWindowNew((event: OnWindowNewEvent) => {
              event.handler.setWebController(null);
              if (event.targetUrl && /^https?:\/\//i.test(event.targetUrl)) {
                this.onOpenExternalLink(event.targetUrl);
              }
            })
            .onPageEnd(() => {
              this.loaded = true;
              const dark = this.isDarkTheme();
              if (this.isHtmlRender) {
                if (this.appliedDarkMode !== dark) {
                  this.appliedDarkMode = dark;
                  this.pushThemeMessage(dark);
                }
              } else {
                this.appliedDarkMode = dark;
                this.pushFallbackThemeCss(dark);
              }
              if (this.nested) {
                this.probeOverflow();
                this.scheduleProbe(260);
              }
            })
            .onTouch((event: TouchEvent) => {
              if (this.nested && this.loaded && event.type === TouchType.Up) {
                this.scheduleProbe(180);
              }
            })
            .onErrorReceive((event: OnErrorReceiveEvent) => {
              if (event && event.request && !event.request.isMainFrame()) return;
              this.loaded = true;
              this.onLoadError();
            })
            .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
              if (event && event.request && !event.request.isMainFrame()) return;
              const code = event && event.response ? event.response.getResponseCode() : 0;
              if (code >= 400) {
                this.loaded = true;
                this.onLoadError();
              }
            })
            .onRenderExited(() => {
              this.handleRenderCrash();
            })
        }, (key: number) => 'web:' + key)
      }
      if (!this.loaded) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color($r('app.color.muted'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgHex())
    .accessibilityText(this.title || 'HTML 内容')
  }
}

@Component
export struct ThreadHtmlRenderCard {
  connection: T3Client | undefined = undefined;
  @Prop entry: HtmlRenderEntry = {
    id: '',
    itemId: '',
    runId: '',
    render: { attachmentId: '', title: 'HTML', height: 240, heights: [] }
  };
  @Prop @Watch('onScopeChange') scopeKey: string = '';
  onOpenFullscreen: (entry: HtmlRenderEntry, uri: string) => void = () => {};
  onOpenExternalLink: (url: string) => void = () => {};

  @State uri: string = '';
  @State loading: boolean = false;
  @State failed: boolean = false;
  @State frameWidth: number = 360;
  @State measuredHeight: number = 0;
  @State attempt: number = 0;
  private loadSeq: number = 0;
  private retriedAfterError: boolean = false;
  private lastAttachmentId: string = '';

  aboutToAppear(): void {
    this.lastAttachmentId = this.entry.render.attachmentId;
    void this.resolveUrl(false);
  }

  aboutToDisappear(): void {
    this.loadSeq += 1;
  }

  private onScopeChange(): void {
    const currentId = this.entry.render.attachmentId;
    if (currentId !== this.lastAttachmentId) {
      this.lastAttachmentId = currentId;
      this.uri = '';
      this.measuredHeight = 0;
      this.failed = false;
      this.retriedAfterError = false;
      void this.resolveUrl(false);
      return;
    }
    if (!this.uri && !this.loading) {
      void this.resolveUrl(false);
    }
  }

  private async resolveUrl(forceRefresh: boolean): Promise<void> {
    const conn = this.connection;
    const attachmentId = this.entry.render.attachmentId;
    if (!conn || !conn.ready || !attachmentId) return;
    if (this.uri && !forceRefresh) return;
    const seq = ++this.loadSeq;
    this.loading = true;
    this.failed = false;
    try {
      const next = await conn.htmlRenderUrl(attachmentId, this.entry.render.title);
      if (seq !== this.loadSeq) return;
      this.loading = false;
      if (next && next !== this.uri) {
        this.uri = next;
      } else if (next) {
        this.attempt += 1;
      } else {
        this.failed = true;
      }
    } catch (_) {
      if (seq !== this.loadSeq) return;
      this.loading = false;
      this.failed = true;
    }
  }

  private handleLoadError(): void {
    if (this.retriedAfterError) {
      this.failed = true;
      return;
    }
    this.retriedAfterError = true;
    void this.resolveUrl(true);
  }

  private currentHeight(): number {
    if (this.measuredHeight > 0) {
      return Math.min(htmlRenderFrameHeight(this.entry.render, this.frameWidth), Math.max(80, this.measuredHeight));
    }
    return htmlRenderFrameHeight(this.entry.render, this.frameWidth);
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: Space.xs }) {
        Text(this.entry.render.title || 'HTML')
          .fontSize(FontSize.caption)
          .fontColor($r('app.color.muted'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.uri && !this.failed) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ui_expand'))
              .width(13)
              .height(13)
              .accessibilityLevel('no')
          }
          .width(28)
          .height(28)
          .backgroundColor($r('app.color.card'))
          .border({ width: Sizes.hairline, color: $r('app.color.border') })
          .accessibilityText('全屏查看 ' + (this.entry.render.title || 'HTML'))
          .onClick(() => this.onOpenFullscreen(this.entry, this.uri))
        }
      }
      .width('100%')
      .height(32)
      .alignItems(VerticalAlign.Center)

      Column() {
        if (this.uri && !this.failed) {
          ForEach([this.uri + ':' + this.attempt], (_key: string) => {
            HtmlRenderWebView({
              uri: this.uri,
              title: this.entry.render.title,
              nested: true,
              isHtmlRender: true,
              onOpenExternalLink: this.onOpenExternalLink,
              onLoadError: () => this.handleLoadError(),
              onMeasuredContent: (height: number, _overflowY: boolean) => {
                if (height > 0 && height <= 2000 && Math.abs(height - this.measuredHeight) > 8) {
                  this.measuredHeight = height;
                }
              }
            })
          }, (key: string) => key)
        } else if (this.failed) {
          Column({ space: 6 }) {
            Text('页面暂不可用')
              .fontSize(FontSize.callout)
              .fontColor($r('app.color.muted'))
            Button('点按重试', { type: ButtonType.Normal })
              .fontSize(FontSize.caption)
              .fontColor($r('app.color.primary_text'))
              .backgroundColor($r('app.color.card'))
              .border({ width: Sizes.hairline, color: $r('app.color.border') })
              .borderRadius(Radius.badge)
              .constraintSize({ minHeight: 32 })
              .padding({ left: 12, right: 12 })
              .onClick(() => {
                this.retriedAfterError = false;
                this.failed = false;
                void this.resolveUrl(true);
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Column() {
            LoadingProgress().width(22).height(22).color($r('app.color.muted'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .height(this.currentHeight())
      .borderRadius(Radius.tool)
      .clip(true)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const w = Number(newArea.width);
        if (Number.isFinite(w) && w >= 120 && Math.abs(w - this.frameWidth) >= 8) {
          this.frameWidth = w;
        }
      })
    }
    .width('100%')
    .margin({ bottom: 4 })
  }
}
