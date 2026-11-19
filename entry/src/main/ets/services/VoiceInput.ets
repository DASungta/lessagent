import { speechRecognizer } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { VoiceFrames, VoiceState, VoiceTranscript } from '../protocol/Voice';

export class VoiceInput {
  private engine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private capturer: audio.AudioCapturer | undefined = undefined;
  private generation: number = 0;
  private session: string = '';
  private phase: string = 'idle';
  private frames: VoiceFrames = new VoiceFrames();
  private transcript: VoiceTranscript = new VoiceTranscript();
  private timer: number = -1;
  private update: (state: VoiceState) => void = () => {};

  private emit(phase: string, message: string = ''): void {
    this.phase = phase;
    this.update({ phase, text: this.transcript.text, message });
  }

  async start(update: (state: VoiceState) => void): Promise<void> {
    const generation = ++this.generation;
    await this.release();
    if (generation !== this.generation) return;
    this.update = update; this.transcript = new VoiceTranscript(); this.frames.clear();
    this.session = 'voice-' + Date.now() + '-' + generation;
    const session = this.session;
    this.emit('preparing', '正在准备设备端识别…');
    try {
      const engine = await speechRecognizer.createEngine({ language: 'zh-CN', online: 1 });
      if (generation !== this.generation) { engine.shutdown(); return; }
      this.engine = engine;
      const capturer = await audio.createAudioCapturer({
        streamInfo: { samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: audio.AudioChannel.CHANNEL_1, sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW },
        capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 }
      });
      if (generation !== this.generation) { await capturer.release(); return; }
      this.capturer = capturer;
      capturer.on('readData', (buffer: ArrayBuffer) => {
        if (generation !== this.generation || (this.phase !== 'recording' && this.phase !== 'finishing')) return;
        try {
          for (const frame of this.frames.push(new Uint8Array(buffer))) engine.writeAudio(session, frame);
        } catch (_) { void this.fail(generation, '语音数据处理失败，请重新录入'); }
      });
      capturer.on('audioInterrupt', (event: audio.InterruptEvent) => {
        if (generation === this.generation && event.eventType === audio.InterruptType.INTERRUPT_TYPE_BEGIN)
          void this.fail(generation, '麦克风被其他应用中断，请重新录入');
      });
      engine.setListener({
        onStart: (id: string, _message: string): void => {
          if (generation !== this.generation || id !== session) return;
          this.clearTimer(); this.emit('recording', '正在聆听，最长 60 秒');
          void capturer.start().then(() => {
            if (generation !== this.generation || this.phase !== 'recording') return;
            this.timer = setTimeout(() => { void this.finish(); }, 60000);
          }).catch(() => { void this.fail(generation, '无法启动麦克风，请检查权限或占用'); });
        },
        onEvent: (_id: string, _code: number, _message: string): void => {},
        onResult: (id: string, result: speechRecognizer.SpeechRecognitionResult): void => {
          if (generation !== this.generation || id !== session) return;
          this.transcript.accept(result.result, result.isFinal);
          this.emit(this.phase);
          if (result.isLast) void this.complete(generation);
        },
        onComplete: (id: string, _message: string): void => {
          if (id === session) void this.complete(generation);
        },
        onError: (id: string, code: number, _message: string): void => {
          if (id === session) void this.fail(generation, '设备端识别失败（' + code + '），请重试或键盘输入');
        }
      });
      this.timer = setTimeout(() => { void this.fail(generation, '设备端语音服务未响应，请重试'); }, 10000);
      engine.startListening({ sessionId: session,
        audioInfo: { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 } });
    } catch (_) {
      await this.fail(generation, '设备端中文识别不可用，请检查系统语音能力后重试。不会改用云端识别。');
    }
  }

  async finish(): Promise<void> {
    if (this.phase !== 'recording') return;
    const generation = this.generation;
    this.emit('finishing', '正在完成识别…'); this.clearTimer();
    try {
      if (this.capturer) { await this.capturer.stop(); this.capturer.off('readData'); }
      if (generation !== this.generation) return;
      const frame = this.frames.finish();
      if (frame) this.engine?.writeAudio(this.session, frame);
      this.timer = setTimeout(() => { void this.fail(generation, '识别结果等待超时，请重新录入'); }, 10000);
      this.engine?.finish(this.session);
    } catch (_) { await this.fail(generation, '完成识别失败，请重新录入'); }
  }

  private async complete(generation: number): Promise<void> {
    if (generation !== this.generation) return;
    const ending = ++this.generation; await this.release();
    if (ending !== this.generation) return;
    this.emit('ready', this.transcript.text.trim() ? '请检查文字后加入草稿' : '没有识别到语音，请重试');
  }

  private async fail(generation: number, message: string): Promise<void> {
    if (generation !== this.generation) return;
    const ending = ++this.generation; this.transcript = new VoiceTranscript(); await this.release();
    if (ending === this.generation) this.emit('error', message);
  }

  async cancel(): Promise<void> {
    ++this.generation; this.transcript = new VoiceTranscript(); this.phase = 'idle';
    await this.release();
  }

  private clearTimer(): void { if (this.timer >= 0) clearTimeout(this.timer); this.timer = -1; }
  private async release(): Promise<void> {
    this.clearTimer(); this.frames.clear();
    const engine = this.engine; const capturer = this.capturer;
    this.engine = undefined; this.capturer = undefined;
    try { engine?.cancel(this.session); } catch (_) { }
    try { engine?.shutdown(); } catch (_) { }
    if (capturer) {
      try { capturer.off('readData'); } catch (_) { }
      try { await capturer.stop(); } catch (_) { }
      try { await capturer.release(); } catch (_) { this.emit('error', '麦克风资源释放失败，请退出应用检查系统麦克风指示'); }
    }
  }
}
