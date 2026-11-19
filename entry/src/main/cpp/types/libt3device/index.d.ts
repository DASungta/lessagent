export interface DecoderStats {
  epoch: number;
  ready: boolean;
  width: number;
  height: number;
  rendered: number;
  dropped: number;
  queued: number;
  error: string;
}
export const start: (surfaceId: string, width: number, height: number) => number;
/** 0 accepted, 1 needs keyframe/backpressure, 2 stale or stopped. */
export const push: (epoch: number, data: ArrayBuffer, timestampUs: number, key: boolean) => number;
export const stop: (epoch: number) => void;
export const stats: () => DecoderStats;
