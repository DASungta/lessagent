import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ComposerDraft, composerDraft } from '../protocol/R4';
import { record, objects } from '../protocol/Wire';

interface DraftFile { version: number; drafts: ComposerDraft[]; }

// Draft bodies are not credentials, but they can contain user text; the file stays app-private.
export class DraftStore {
  private path: string;
  constructor(filesDir: string) { this.path = filesDir + '/r4-drafts-v1.json'; }
  async load(): Promise<ComposerDraft[]> {
    try {
      const row = record(JSON.parse(fileIo.readTextSync(this.path)) as Object);
      if (row.version !== 1) throw new Error('草稿存储版本无效');
      return objects(row.drafts).map(composerDraft);
    } catch (error) {
      if ((error as BusinessError).code === 13900002) return [];
      throw new Error('草稿记录不可读或损坏，未覆盖原记录');
    }
  }
  async save(drafts: ComposerDraft[]): Promise<void> {
    const file: DraftFile = { version: 1, drafts: drafts.map(composerDraft) };
    const content = JSON.stringify(file);
    const temporary = this.path + '.tmp';
    const fd = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(fd.fd, content);
      fileIo.fsyncSync(fd.fd);
    } finally { fileIo.closeSync(fd); }
    if (fileIo.readTextSync(temporary) !== content) throw new Error('草稿回读校验失败');
    fileIo.renameSync(temporary, this.path);
  }
}

export let draftStore: DraftStore | undefined = undefined;
export async function prepareDrafts(filesDir: string): Promise<void> {
  draftStore = new DraftStore(filesDir);
}

