import { media } from '@kit.MediaKit';
import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';
import { AppButton } from './ui/AppButton';

function formatClock(ms: number): string {
  const totalSec = Number.isFinite(ms) ? Math.max(0, Math.floor(ms / 1000)) : 0;
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  return min + ':' + (sec < 10 ? '0' + sec : String(sec));
}

@Component
export struct AudioPlayerView {
  @Prop @Watch('onUriChange') uri: string = '';
  @Prop title: string = '';
  @StorageLink('t3Foreground') @Watch('onForegroundChange') foreground: boolean = true;

  @State stateText: string = '正在加载音频…';
  @State ready: boolean = false;
  @State playing: boolean = false;
  @State currentMs: number = 0;
  @State durationMs: number = 0;
  @State error: string = '';

  private player: media.AVPlayer | undefined = undefined;
  private generation: number = 0;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    void this.loadAudio();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.generation += 1;
    void this.releasePlayer();
  }

  private onUriChange(): void {
    void this.loadAudio();
  }

  private onForegroundChange(): void {
    if (!this.foreground && this.playing && this.player) {
      void this.player.pause().catch(() => {});
    }
  }

  private async releasePlayer(): Promise<void> {
    const active = this.player;
    this.player = undefined;
    if (!active) return;
    try { await active.release(); } catch (_) {}
  }

  private async loadAudio(): Promise<void> {
    const gen = ++this.generation;
    await this.releasePlayer();
    this.ready = false;
    this.playing = false;
    this.currentMs = 0;
    this.durationMs = 0;
    this.error = '';
    if (!this.uri) {
      this.stateText = '缺少音频地址';
      return;
    }
    this.stateText = '正在加载音频…';
    try {
      const av = await media.createAVPlayer();
      if (!this.alive || gen !== this.generation) {
        await av.release().catch(() => {});
        return;
      }
      this.player = av;
      av.on('stateChange', (state: string) => {
        if (!this.alive || gen !== this.generation) return;
        if (state === 'initialized') {
          void av.prepare().catch(() => {});
        } else if (state === 'prepared') {
          this.ready = true;
          this.playing = false;
          this.durationMs = av.duration > 0 ? av.duration : this.durationMs;
          this.stateText = '已就绪';
        } else if (state === 'playing') {
          this.ready = true;
          this.playing = true;
          this.stateText = '正在播放';
        } else if (state === 'paused') {
          this.playing = false;
          this.stateText = '已暂停';
        } else if (state === 'completed') {
          this.playing = false;
          this.currentMs = this.durationMs;
          this.stateText = '播放完成';
        } else if (state === 'error') {
          this.playing = false;
          this.ready = false;
          this.error = '音频解码或加载失败';
          this.stateText = '播放出错';
        }
      });
      av.on('durationUpdate', (dur: number) => {
        if (this.alive && gen === this.generation && dur >= 0) this.durationMs = dur;
      });
      av.on('timeUpdate', (time: number) => {
        if (this.alive && gen === this.generation && time >= 0) this.currentMs = time;
      });
      av.on('error', () => {
        if (!this.alive || gen !== this.generation) return;
        this.playing = false;
        this.ready = false;
        this.error = '无法播放此音频文件，可尝试保存或系统打开';
      });
      av.url = this.uri;
    } catch (_) {
      if (this.alive && gen === this.generation) {
        this.error = '音频播放器初始化失败';
        this.stateText = '不可用';
      }
    }
  }

  private async togglePlay(): Promise<void> {
    const av = this.player;
    if (!av || !this.ready) return;
    this.error = '';
    try {
      if (this.playing) await av.pause();
      else await av.play();
    } catch (_) {
      this.error = '播放控制失败，请重试';
    }
  }

  private seekBy(deltaMs: number): void {
    const av = this.player;
    if (!av || !this.ready || this.durationMs <= 0) return;
    const next = Math.max(0, Math.min(this.durationMs, this.currentMs + deltaMs));
    this.currentMs = next;
    try { av.seek(next); } catch (_) {}
  }

  private seekTo(ms: number): void {
    const av = this.player;
    if (!av || !this.ready || this.durationMs <= 0) return;
    const next = Math.max(0, Math.min(this.durationMs, Math.round(ms)));
    this.currentMs = next;
    try { av.seek(next); } catch (_) {}
  }

  build() {
    Column({ space: Space.md }) {
      Column({ space: Space.xs }) {
        Text(this.title || '音频预览')
          .fontSize(FontSize.headline)
          .lineHeight(LineHeight.headline)
          .fontWeight(Weight.semibold)
          .fontColor($r('app.color.ink'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
        Text(this.stateText)
          .fontSize(FontSize.caption)
          .fontColor($r('app.color.muted'))
      }.width('100%').alignItems(HorizontalAlign.Center)

      if (this.error) {
        Column({ space: Space.xs }) {
          Text(this.error)
            .fontSize(FontSize.callout)
            .fontColor($r('app.color.danger'))
            .textAlign(TextAlign.Center)
          AppButton({
            label: '重试加载',
            kind: 'secondary',
            compact: true,
            onTap: () => { void this.loadAudio(); }
          })
        }.width('100%').alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: Space.xs }) {
          Slider({
            value: this.durationMs > 0 ? this.currentMs : 0,
            min: 0,
            max: this.durationMs > 0 ? this.durationMs : 100,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .enabled(this.ready && this.durationMs > 0)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.seekTo(value);
              }
            })
          Row() {
            Text(formatClock(this.currentMs)).fontSize(FontSize.caption).fontColor($r('app.color.muted'))
            Blank()
            Text(formatClock(this.durationMs)).fontSize(FontSize.caption).fontColor($r('app.color.muted'))
          }.width('100%')
        }.width('100%')

        Row({ space: Space.sm }) {
          AppButton({
            label: '-15s',
            kind: 'secondary',
            compact: true,
            disabled: !this.ready || this.durationMs <= 0,
            onTap: () => this.seekBy(-15000)
          })
          AppButton({
            label: this.playing ? '暂停' : '播放',
            kind: 'primary',
            compact: true,
            disabled: !this.ready,
            onTap: () => { void this.togglePlay(); }
          })
          AppButton({
            label: '+15s',
            kind: 'secondary',
            compact: true,
            disabled: !this.ready || this.durationMs <= 0,
            onTap: () => this.seekBy(15000)
          })
        }.justifyContent(FlexAlign.Center).width('100%')
      }
    }
    .width('100%')
    .padding(Space.lg)
    .backgroundColor($r('app.color.card'))
    .borderRadius(Radius.card)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}
