export function settingsMatch(query: string, keywords: string): boolean {
  return query.trim().toLowerCase().split(/\s+/).every(word => keywords.toLowerCase().includes(word));
}

export function appearanceMode(value: string): number {
  if (value === 'system') return -1;
  if (value === 'light') return 1;
  if (value === 'dark') return 0;
  throw new Error('外观选项无效');
}

export function diagnosticSummary(version: string, environments: number, projects: number, archived: number): string {
  // Only fixed fields; never serialize environment objects, URLs, logs or messages.
  const counts = [environments, projects, archived];
  if (!counts.every(value => Number.isSafeInteger(value) && value >= 0)) throw new Error('诊断计数无效');
  if (!/^[a-zA-Z0-9.+_-]{1,64}$/.test(version)) throw new Error('版本信息无效');
  return `简码 (LessAgent)\n客户端版本: ${version}\n环境数: ${environments}\n项目数: ${projects}\n归档会话数: ${archived}\n平台: HarmonyOS\n不包含地址、账号、凭据或消息内容。`;
}

export function followUpDelivery(selected: string, running: boolean, preference: string): string {
  if (!['queue', 'steer'].includes(preference) || !['auto', 'queue', 'steer'].includes(selected)) {
    throw new Error('消息发送方式无效');
  }
  return selected === 'auto' && running ? preference : selected;
}
