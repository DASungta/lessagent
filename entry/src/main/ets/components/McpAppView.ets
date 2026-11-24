import { webview } from '@kit.ArkWeb';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { harmonyHtmlRenderTheme, shouldAllowHtmlRenderNavigation } from '../protocol/HtmlRender';
import {
  buildMcpAppHostContext,
  buildMcpAppJsonRpcError,
  buildMcpAppJsonRpcNotification,
  buildMcpAppJsonRpcResult,
  clampMcpAppInlineHeight,
  MCP_APP_BRIDGE_SHIM_JS,
  MCP_APP_INLINE_MAX_HEIGHT,
  MCP_APP_PROTOCOL_VERSION,
  McpAppEntry
} from '../protocol/McpApp';
import { optionalRecord } from '../protocol/Wire';
import { currentAppearance } from '../services/Appearance';
import { T3Client } from '../services/T3Client';
import { AppButton } from './ui/AppButton';

class McpAppBridgeProxy {
  private handler: (raw: string) => void;
  constructor(handler: (raw: string) => void) {
    this.handler = handler;
  }
  post(raw: string): void {
    this.handler(raw);
  }
}

@Component
export struct McpAppView {
  connection: T3Client | undefined = undefined;
  @Prop entry: McpAppEntry;
  @Prop threadId: string = '';
  @Prop fullscreen: boolean = false;
  @StorageProp('t3SystemColorMode') @Watch('onThemeChange') systemColorMode: number = -1;
  @StorageProp('t3AppearanceMode') @Watch('onThemeChange') appearanceMode: string = '';
  onExpand: (entry: McpAppEntry) => void = () => {};
  onExitFullscreen: () => void = () => {};
  onOpenExternalLink: (url: string) => void = () => {};
  onSendMessage: (text: string) => Promise<void> = async () => {};

  @State uri: string = '';
  @State loading: boolean = true;
  @State error: string = '';
  @State frameHeight: number = 340;
  @State renderKey: number = 0;

  private controller: webview.WebviewController = new webview.WebviewController();
  private proxy: McpAppBridgeProxy | undefined = undefined;
  private toolDefinition: Object | undefined = undefined;
  private controllerAttached: boolean = false;
  private initialized: boolean = false;
  private alive: boolean = false;
  private generation: number = 0;
  private areaWidth: number = 360;
  private areaHeight: number = MCP_APP_INLINE_MAX_HEIGHT;

  private isDark(): boolean {
    const mode = this.appearanceMode || currentAppearance;
    if (mode === 'dark') return true;
    if (mode === 'light') return false;
    return this.systemColorMode === 0;
  }

  aboutToAppear(): void {
    this.alive = true;
    this.proxy = new McpAppBridgeProxy((raw: string) => {
      void this.handleBridgeMessage(raw);
    });
    void this.loadApp();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.generation += 1;
  }

  private async loadApp(): Promise<void> {
    const conn = this.connection;
    if (!conn || !conn.ready) {
      this.loading = false;
      this.error = '环境未连接，无法加载 MCP App';
      return;
    }
    const gen = ++this.generation;
    this.loading = true;
    this.error = '';
    this.initialized = false;
    try {
      const url = await conn.mcpAppAssetUrl(this.entry.app);
      if (!this.alive || gen !== this.generation) return;
      this.uri = url;
      try {
        const info = await conn.mcpAppToolInfo(this.threadId, this.entry.itemId, this.entry.app.tool);
        if (this.alive && gen === this.generation) this.toolDefinition = info.tool;
      } catch (_) {}
      if (this.controllerAttached && this.uri) {
        try { this.controller.loadUrl(this.uri); } catch (_) {}
      }
    } catch (reason) {
      if (this.alive && gen === this.generation) {
        this.loading = false;
        this.error = (reason as Error).message || 'MCP App 加载失败';
      }
    }
  }

  private postToPage(jsonPayload: string): void {
    if (!this.controllerAttached || !this.alive) return;
    const script = 'if(window.__t3McpReceive){window.__t3McpReceive(' + JSON.stringify(jsonPayload) + ');}';
    try {
      void this.controller.runJavaScript(script).catch(() => {});
    } catch (_) {}
  }

  private hostContext(): Record<string, Object> {
    const theme = harmonyHtmlRenderTheme(this.isDark());
    return buildMcpAppHostContext(
      theme.appearance,
      theme.variables,
      this.fullscreen ? 'fullscreen' : 'inline',
      this.areaWidth,
      this.areaHeight,
      this.toolDefinition
    );
  }

  private onThemeChange(): void {
    if (!this.initialized) return;
    this.postToPage(buildMcpAppJsonRpcNotification('ui/notifications/host-context-changed', this.hostContext()));
  }

  private async handleBridgeMessage(raw: string): Promise<void> {
    if (!this.alive || !raw || raw.length > 262144) return;
    let parsed: Record<string, Object> | undefined = undefined;
    try {
      parsed = optionalRecord(JSON.parse(raw) as Object);
    } catch (_) {
      return;
    }
    if (!parsed || parsed.jsonrpc !== '2.0') return;
    const method = typeof parsed.method === 'string' ? parsed.method : '';
    const hasId = typeof parsed.id === 'string' || typeof parsed.id === 'number';
    const id = hasId ? (parsed.id as string | number) : '';
    const params = optionalRecord(parsed.params) || ({} as Record<string, Object>);

    if (method === 'ui/notifications/size-changed') {
      if (!this.fullscreen && typeof params.height === 'number' && Number.isFinite(params.height)) {
        this.frameHeight = clampMcpAppInlineHeight(params.height as number);
      }
      return;
    }

    if (method === 'ui/notifications/initialized') {
      this.initialized = true;
      void this.pushStoredToolCall();
      return;
    }

    if (method === 'ui/initialize' && hasId) {
      const hostInfo: Record<string, Object> = {};
      hostInfo['name'] = 'T3 Code Harmony';
      hostInfo['version'] = '1.0.0';
      const emptyCap1: Record<string, Object> = {};
      const emptyCap2: Record<string, Object> = {};
      const emptyCap3: Record<string, Object> = {};
      const emptyCap4: Record<string, Object> = {};
      const hostCaps: Record<string, Object> = {};
      hostCaps['openLinks'] = emptyCap1;
      hostCaps['serverTools'] = emptyCap2;
      hostCaps['serverResources'] = emptyCap3;
      hostCaps['updateModelContext'] = emptyCap4;
      const result: Record<string, Object> = {};
      result['protocolVersion'] = MCP_APP_PROTOCOL_VERSION;
      result['hostInfo'] = hostInfo;
      result['hostCapabilities'] = hostCaps;
      result['hostContext'] = this.hostContext();
      this.postToPage(buildMcpAppJsonRpcResult(id, result));
      return;
    }

    if (method === 'ui/open-link') {
      const url = typeof params.url === 'string' ? params.url.trim() : '';
      if (/^https?:\/\//i.test(url)) {
        this.onOpenExternalLink(url);
        if (hasId) this.postToPage(buildMcpAppJsonRpcResult(id, {} as Record<string, Object>));
      } else if (hasId) {
        this.postToPage(buildMcpAppJsonRpcError(id, -32602, '仅支持打开 http(s) 链接'));
      }
      return;
    }

    if (method === 'ui/request-display-mode' && hasId) {
      const mode = typeof params.mode === 'string' ? params.mode : 'inline';
      if (mode === 'fullscreen' && !this.fullscreen) {
        this.onExpand(this.entry);
      } else if (mode === 'inline' && this.fullscreen) {
        this.onExitFullscreen();
      }
      const modeResult: Record<string, Object> = {};
      modeResult['mode'] = this.fullscreen ? 'fullscreen' : 'inline';
      this.postToPage(buildMcpAppJsonRpcResult(id, modeResult));
      return;
    }

    if (method === 'ui/message' && hasId) {
      const content = Array.isArray(params.content) ? (params.content as Object[]) : [];
      const parts: string[] = [];
      for (const block of content) {
        const rec = optionalRecord(block);
        if (rec && rec.type === 'text' && typeof rec.text === 'string' && rec.text.trim()) {
          parts.push(rec.text.trim());
        }
      }
      const text = parts.join('\n').trim();
      if (!text) {
        this.postToPage(buildMcpAppJsonRpcError(id, -32602, '消息内容为空'));
        return;
      }
      try {
        await this.onSendMessage(text);
        this.postToPage(buildMcpAppJsonRpcResult(id, {} as Record<string, Object>));
      } catch (reason) {
        this.postToPage(buildMcpAppJsonRpcError(id, -32000, (reason as Error).message || '发送失败'));
      }
      return;
    }

    const conn = this.connection;
    if (!conn || !conn.ready) {
      if (hasId) this.postToPage(buildMcpAppJsonRpcError(id, -32000, '环境未连接'));
      return;
    }

    if (method === 'tools/call' && hasId) {
      const name = typeof params.name === 'string' ? params.name.trim() : '';
      const args = optionalRecord(params.arguments) || ({} as Record<string, Object>);
      if (!name) {
        this.postToPage(buildMcpAppJsonRpcError(id, -32602, '缺少工具名'));
        return;
      }
      try {
        const res = await conn.mcpAppCallTool(this.threadId, this.entry.itemId, name, args);
        this.postToPage(buildMcpAppJsonRpcResult(id, res as Object));
      } catch (reason) {
        this.postToPage(buildMcpAppJsonRpcError(id, -32000, (reason as Error).message || '工具调用失败'));
      }
      return;
    }

    if (method === 'resources/read' && hasId) {
      const uri = typeof params.uri === 'string' ? params.uri.trim() : '';
      if (!uri) {
        this.postToPage(buildMcpAppJsonRpcError(id, -32602, '缺少资源 URI'));
        return;
      }
      try {
        const res = await conn.mcpAppReadResource(this.threadId, this.entry.itemId, uri);
        this.postToPage(buildMcpAppJsonRpcResult(id, res));
      } catch (reason) {
        this.postToPage(buildMcpAppJsonRpcError(id, -32000, (reason as Error).message || '资源读取失败'));
      }
      return;
    }

    if (method === 'ui/update-model-context' && hasId) {
      const content = Array.isArray(params.content) ? (params.content as Object[]) : undefined;
      const structured = optionalRecord(params.structuredContent);
      try {
        await conn.mcpAppUpdateModelContext(this.threadId, this.entry.itemId, this.threadId, content, structured);
        this.postToPage(buildMcpAppJsonRpcResult(id, {} as Record<string, Object>));
      } catch (reason) {
        this.postToPage(buildMcpAppJsonRpcError(id, -32000, (reason as Error).message || '上下文更新失败'));
      }
      return;
    }

    if (hasId) {
      this.postToPage(buildMcpAppJsonRpcError(id, -32601, '不支持的方法：' + method));
    }
  }

  private async pushStoredToolCall(): Promise<void> {
    const conn = this.connection;
    if (!conn || !conn.ready || !this.entry.itemId) return;
    try {
      const fullItem = await conn.turnItem(this.entry.itemId);
      if (!fullItem || !this.alive) return;
      if (fullItem.input !== undefined) {
        const inputParams: Record<string, Object> = {};
        inputParams['arguments'] = fullItem.input;
        this.postToPage(buildMcpAppJsonRpcNotification('ui/notifications/tool-input', inputParams));
      }
      const out = optionalRecord(fullItem.output);
      if (out && out.result !== undefined) {
        this.postToPage(buildMcpAppJsonRpcNotification('ui/notifications/tool-result', out.result));
      }
    } catch (_) {}
  }

  build() {
    Column({ space: 0 }) {
      if (!this.fullscreen) {
        Row({ space: Space.xs }) {
          Text(this.entry.app.title)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontWeight(Weight.medium)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button('刷新', { type: ButtonType.Normal })
            .height(28)
            .fontSize(FontSize.badge)
            .fontColor($r('app.color.muted'))
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.renderKey += 1; void this.loadApp(); })
          Button('全屏', { type: ButtonType.Normal })
            .height(28)
            .fontSize(FontSize.badge)
            .fontColor($r('app.color.primary_text'))
            .backgroundColor(Color.Transparent)
            .onClick(() => this.onExpand(this.entry))
        }
        .width('100%')
        .padding({ left: Space.sm, right: Space.xs, top: Space.xxs, bottom: Space.xxs })
        .border({ width: { bottom: Sizes.hairline }, color: { bottom: $r('app.color.separator') } })
        .alignItems(VerticalAlign.Center)
      }

      if (this.error) {
        Column({ space: Space.xs }) {
          Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
          AppButton({
            label: '重试',
            kind: 'secondary',
            compact: true,
            onTap: () => { void this.loadApp(); }
          })
        }.width('100%').padding(Space.md).alignItems(HorizontalAlign.Start)
      } else if (this.uri) {
        Stack({ alignContent: Alignment.Center }) {
          Web({ src: this.uri, controller: this.controller })
            .key('mcp-app-' + this.entry.itemId + '-' + this.renderKey + '-' + (this.fullscreen ? 'fs' : 'in'))
            .width('100%')
            .height(this.fullscreen ? '100%' : this.frameHeight)
            .javaScriptAccess(true)
            .domStorageAccess(false)
            .fileAccess(false)
            .geolocationAccess(false)
            .mixedMode(MixedMode.None)
            .javaScriptProxy({
              object: this.proxy as Object,
              name: '__t3McpHost',
              methodList: ['post'],
              controller: this.controller
            })
            .onControllerAttached(() => {
              this.controllerAttached = true;
            })
            .onPageEnd(() => {
              this.loading = false;
              try {
                void this.controller.runJavaScript(MCP_APP_BRIDGE_SHIM_JS).catch(() => {});
              } catch (_) {}
            })
            .onLoadIntercept((event) => {
              const req = event?.data;
              const target = req ? req.getRequestUrl() : '';
              if (!target || shouldAllowHtmlRenderNavigation(target, this.uri, req ? req.isMainFrame() : true)) {
                return false;
              }
              if (/^https?:\/\//i.test(target)) {
                this.onOpenExternalLink(target);
              }
              return true;
            })
            .onErrorReceive((event) => {
              if (event?.request?.isMainFrame()) {
                this.loading = false;
                this.error = 'MCP App 页面加载失败';
              }
            })
          if (this.loading) {
            Text('正在加载 MCP App…')
              .fontSize(FontSize.caption)
              .fontColor($r('app.color.muted'))
              .padding(Space.sm)
              .backgroundColor($r('app.color.card'))
              .borderRadius(Radius.tool)
          }
        }
        .width('100%')
        .height(this.fullscreen ? '100%' : this.frameHeight)
        .onAreaChange((_, area: Area) => {
          const w = Number(area.width);
          const h = Number(area.height);
          if (Number.isFinite(w) && w > 0) this.areaWidth = w;
          if (Number.isFinite(h) && h > 0) this.areaHeight = h;
        })
      } else {
        Text('正在准备 MCP App…')
          .fontSize(FontSize.caption)
          .fontColor($r('app.color.muted'))
          .padding(Space.md)
      }
    }
    .width('100%')
    .height(this.fullscreen ? '100%' : undefined)
    .backgroundColor($r('app.color.card'))
    .borderRadius(this.fullscreen ? 0 : Radius.card)
    .border(this.fullscreen ? undefined : { width: Sizes.hairline, color: $r('app.color.border') })
    .clip(true)
  }
}
