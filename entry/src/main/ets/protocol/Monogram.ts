/**
 * 项目双字母色块（ProjectMonogram）的纯逻辑：首字母提取与稳定配色。
 * 只用可擦除的类型语法，供 node --experimental-strip-types 直接测试。
 */

/** color.json 中 monogram_N_fg / monogram_N_bg 的组数。 */
export const MONOGRAM_TONE_COUNT: number = 8;

const SEPARATORS: RegExp = /[\s\-_.\/\\:·,;|+&()\[\]{}<>@#~'"`!?*=^$%]+/;

function isCjk(ch: string): boolean {
  const code = ch.codePointAt(0) ?? 0;
  return (code >= 0x3040 && code <= 0x30ff) || // 平假名 / 片假名
    (code >= 0x3400 && code <= 0x4dbf) || // CJK 扩展 A
    (code >= 0x4e00 && code <= 0x9fff) || // CJK 基本区
    (code >= 0xac00 && code <= 0xd7af) || // 韩文音节
    (code >= 0xf900 && code <= 0xfaff) || // CJK 兼容
    (code >= 0x20000 && code <= 0x3134f); // CJK 扩展 B 以后
}

function isAlnum(ch: string): boolean {
  return /[0-9]/.test(ch) || ch.toLowerCase() !== ch.toUpperCase();
}

function splitWords(name: string): string[] {
  // 只在「小写 → 大写」处拆 camelCase：myProject → my Project，T3Code 保持一个词。
  const spaced = name.replace(/([a-z])([A-Z])/g, '$1 $2');
  return spaced.split(SEPARATORS).filter((word: string) => word.length > 0);
}

/**
 * 提取项目名首字母，最多两个拉丁字符或一个 CJK 字符。
 * - "t3code-harmony" → "TH"；"T3Code" → "T3"；"myProject" → "MP"；"r5" → "R5"
 * - "拉文克劳" → "拉"；空名 → "?"
 */
export function projectInitials(name: string | undefined | null): string {
  const words = splitWords((name ?? '').trim());
  if (words.length === 0) return '?';
  const first = Array.from(words[0]);
  const lead = first[0];
  if (isCjk(lead) || !isAlnum(lead)) return lead;
  if (words.length >= 2) {
    const second = Array.from(words[1])[0];
    if (isAlnum(second) && !isCjk(second)) return (lead + second).toUpperCase();
  }
  const next = first.length > 1 ? first[1] : '';
  if (next && isAlnum(next) && !isCjk(next)) return (lead + next).toUpperCase();
  return lead.toUpperCase();
}

/** FNV-1a 32 位哈希，结果为非负整数。 */
export function stableHash(value: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** 由项目 id 稳定地选出配色序号，范围 [0, count)。 */
export function monogramTone(id: string | undefined | null, count: number = MONOGRAM_TONE_COUNT): number {
  const size = Math.max(1, Math.floor(count));
  return stableHash(id ?? '') % size;
}
