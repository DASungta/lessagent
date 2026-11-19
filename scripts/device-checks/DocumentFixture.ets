import { common } from '@kit.AbilityKit';
import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { EnvironmentDirectory, EnvironmentEntry } from '../protocol/Environment';
import { SavedSession, RecoveryState } from '../protocol/Core';
import { SessionStore } from '../storage/SessionStore';
interface FixtureDocument { name: string; uri: string; content: string; bytes: number; }
interface RemovalAudit { a: EnvironmentEntry; b: EnvironmentEntry; }
interface SaveSelection { expectedNames: string[]; selectedUris: string[]; }
@Entry
@Component
struct DocumentFixture {
  @State report: string = 'Only unique R1 test documents are created or removed';
  @State busy: boolean = false;
  private stage: string = 'start';
  private path(): string {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return context.getApplicationContext().filesDir + '/r1-document-fixture-private.json';
  }
  private async create(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      if (fileIo.accessSync(this.path())) throw new Error('existing fixture');
      const suffix = util.generateRandomUUID();
      const names = ['r1-native-A-' + suffix + '.txt', 'r1-native-B-' + suffix + '.txt'];
      const options = new picker.DocumentSaveOptions(); options.newFileNames = names;
      this.stage = 'system-save';
      const selected = await new picker.DocumentViewPicker().save(options);
      const selection: SaveSelection = { expectedNames: names, selectedUris: selected };
      const selectionFile = fileIo.openSync(this.path() + '.selection', fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(selectionFile.fd, JSON.stringify(selection)); fileIo.fsyncSync(selectionFile.fd); }
      finally { fileIo.closeSync(selectionFile); }
      if (!selected.length) { this.report = 'Cancelled; no fixture written'; return; }
      if (selected.length !== 2) throw new Error('unexpected selection');
      this.stage = 'validate-names';
      const documents: FixtureDocument[] = [];
      for (let index = 0; index < selected.length; index++) {
        const uri = selected[index]; const name = new fileUri.FileUri(uri).name;
        if (!names.includes(name)) throw new Error('unexpected filename');
        const content = name === names[0] ? 'R1 attachment A: native document only.\n' : 'R1 attachment B: native document only.\n';
        const bytes = new util.TextEncoder().encodeInto(content);
        documents.push({ name, uri, content, bytes: bytes.length });
      }
      // Journal owned URIs before writing, so a partial failure remains cleanable.
      this.saveManifest(documents);
      for (const document of documents) {
        this.stage = 'write-owned-document';
        const uri = document.uri; const bytes = new util.TextEncoder().encodeInto(document.content);
        const file = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try { await fileIo.write(file.fd, bytes.buffer as ArrayBuffer); await fileIo.fsync(file.fd); }
        finally { await fileIo.close(file); }
        this.stage = 'readback-owned-document';
        if (await this.readDocument(uri) !== document.content) throw new Error('readback mismatch');
      }
      this.report = 'PASS saved and read back 2 unique test documents';
    } catch (_) { this.report = 'FAIL document fixture at ' + this.stage; }
    finally { this.busy = false; }
  }
  private saveManifest(documents: FixtureDocument[]): void {
    const output = fileIo.openSync(this.path(), fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(output.fd, JSON.stringify(documents)); fileIo.fsyncSync(output.fd); }
    finally { fileIo.closeSync(output); }
  }
  private async readDocument(uri: string): Promise<string> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = (await fileIo.stat(file.fd)).size;
      if (size > 128) throw new Error('file changed');
      if (size === 0) return '';
      const bytes = new ArrayBuffer(size); let offset = 0;
      while (offset < size) {
        const part = new ArrayBuffer(size - offset); const count = await fileIo.read(file.fd, part);
        if (!count) throw new Error('short read');
        new Uint8Array(bytes).set(new Uint8Array(part, 0, count), offset); offset += count;
      }
      return new util.TextDecoder().decodeToString(new Uint8Array(bytes));
    } finally { await fileIo.close(file); }
  }
  private async cleanup(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      this.stage = 'cleanup-manifest';
      const documents = JSON.parse(fileIo.readTextSync(this.path())) as FixtureDocument[];
      if (documents.length !== 2 && documents.length !== 4) throw new Error('invalid fixture');
      for (const document of documents) {
        this.stage = 'cleanup-name';
        if (!/^r1-native-[AB]-[a-zA-Z0-9-]+\.txt$/.test(document.name) || new fileUri.FileUri(document.uri).name !== document.name) throw new Error('invalid filename');
        try {
          this.stage = 'cleanup-readback';
          if (await this.readDocument(document.uri) !== document.content) throw new Error('file changed');
        } catch (error) { if ((error as BusinessError).code !== 13900002) throw error as Error; }
      }
      for (const document of documents) {
        this.stage = 'cleanup-unlink';
        try { fileIo.unlinkSync(document.uri); }
        catch (error) { if ((error as BusinessError).code !== 13900002) throw error as Error; }
        let missing = false;
        this.stage = 'cleanup-reopen';
        try { await this.readDocument(document.uri); }
        catch (error) { if ((error as BusinessError).code === 13900002) missing = true; else throw error as Error; }
        if (!missing) throw new Error('file remains');
      }
      fileIo.unlinkSync(this.path()); this.report = 'PASS removed only recorded test documents';
    } catch (error) { this.report = 'FAIL ' + this.stage + ' code ' + String((error as BusinessError).code || 0) + '; journal retained'; }
    finally { this.busy = false; }
  }
  private async recoverPrevious(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      const current = JSON.parse(fileIo.readTextSync(this.path())) as FixtureDocument[];
      const allowed = JSON.parse(fileIo.readTextSync(this.path() + '.allowed')) as string[];
      if (allowed.length !== 4 || current.some((document: FixtureDocument) => !allowed.includes(document.name))) throw new Error('invalid allowlist');
      const documents: FixtureDocument[] = [];
      const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 4;
      this.stage = 'prior-picker-result';
      const selected = await new picker.DocumentViewPicker().select(options);
      if (!selected.length) return;
      if (selected.length !== 4) throw new Error('select four recorded owned files');
      for (const uri of selected) {
        this.stage = 'prior-name-validation';
        const name = new fileUri.FileUri(uri).name;
        if (!allowed.includes(name) || documents.some((document: FixtureDocument) => document.name === name)) throw new Error('not an allowed fixture');
        this.stage = 'prior-readback'; const content = await this.readDocument(uri);
        const expected = name.startsWith('r1-native-A-') ? 'R1 attachment A: native document only.\n' : 'R1 attachment B: native document only.\n';
        this.stage = 'prior-content-validation';
        if (content !== expected && (content !== '' || current.some((document: FixtureDocument) => document.name === name))) throw new Error('file changed');
        documents.push({ name, uri, content, bytes: content.length });
      }
      this.stage = 'prior-journal'; this.saveManifest(documents); this.report = 'PASS recorded 4 owned fixture files for cleanup';
    } catch (error) { this.report = 'FAIL ' + this.stage + ' code ' + String((error as BusinessError).code || 0) + '; no files removed'; }
    finally { this.busy = false; }
  }
  private async auditRemoval(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const appFiles = context.getApplicationContext().filesDir;
      const input = JSON.parse(fileIo.readTextSync(appFiles + '/r1-product-removal-audit-input.json')) as RemovalAudit;
      const directory = JSON.parse(fileIo.readTextSync(context.filesDir + '/environments-v2.json')) as EnvironmentDirectory;
      if (directory.entries.length !== 1 || JSON.stringify(directory.entries[0]) !== JSON.stringify(input.a)) throw new Error('directory mismatch');
      const session = await new SessionStore<SavedSession>(input.a.credentialRef).load();
      if (!session || session.environmentId !== input.a.environmentId || session.base !== input.a.base || !session.token || session.expiresAt <= Date.now()) throw new Error('A credential mismatch');
      for (const reference of input.a.recovery) {
        const recovery = await new SessionStore<RecoveryState>(reference.alias).load();
        if (!recovery || recovery.environmentId !== input.a.environmentId || recovery.base !== input.a.base || recovery.threadId !== reference.threadId || recovery.pendingId || recovery.pendingKind) throw new Error('A recovery mismatch');
      }
      if (await new SessionStore<SavedSession>(input.b.credentialRef).load() !== undefined) throw new Error('B credential remains');
      for (const reference of input.b.recovery) if (await new SessionStore<RecoveryState>(reference.alias).load() !== undefined) throw new Error('B recovery remains');
      const output = fileIo.openSync(appFiles + '/r1-product-removal-audit.json', fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(output.fd, JSON.stringify({ aDirectoryUnchanged: true, aCredentialValid: true, aRecoveryIntact: true, bCredentialAbsent: true, bRecoveryRecordsAbsent: input.b.recovery.length })); fileIo.fsyncSync(output.fd); }
      finally { fileIo.closeSync(output); }
      this.report = 'PASS native A credential/recovery preserved; B Assets absent';
    } catch (_) { this.report = 'FAIL removal audit; no credential or recovery changed'; }
    finally { this.busy = false; }
  }
  build() {
    Column({ space: 20 }) {
      Text('R1 native document fixture').fontSize(22)
      Text(this.report).fontSize(16)
      Button('保存两份 R1 测试文档').enabled(!this.busy).onClick(() => this.create())
      Button('记录前次测试文档').enabled(!this.busy).onClick(() => this.recoverPrevious())
      Button('清理本轮测试文档').enabled(!this.busy).onClick(() => this.cleanup())
      Button('核对产品移除隔离').enabled(!this.busy).onClick(() => this.auditRemoval())
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
  }
}
