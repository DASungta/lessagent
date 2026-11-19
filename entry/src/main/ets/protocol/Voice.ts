export interface VoiceState {
  phase: string;
  text: string;
  message: string;
}

// Each write must contain a full 20 ms PCM frame; only the final frame is zero-padded.
export class VoiceFrames {
  private pending: Uint8Array = new Uint8Array(0);
  push(bytes: Uint8Array): Uint8Array[] {
    const data = new Uint8Array(this.pending.length + bytes.length);
    data.set(this.pending); data.set(bytes, this.pending.length);
    const frames: Uint8Array[] = [];
    let offset = 0;
    while (offset + 640 <= data.length) {
      frames.push(data.slice(offset, offset + 640)); offset += 640;
    }
    this.pending = data.slice(offset);
    return frames;
  }
  finish(): Uint8Array | undefined {
    if (!this.pending.length) return undefined;
    const result = new Uint8Array(640);
    result.set(this.pending); this.clear();
    return result;
  }
  clear(): void { this.pending = new Uint8Array(0); }
}

export class VoiceTranscript {
  private complete: string = '';
  text: string = '';
  accept(value: string, isFinal: boolean): string {
    this.text = this.complete + value;
    if (isFinal) this.complete = this.text;
    return this.text;
  }
}
