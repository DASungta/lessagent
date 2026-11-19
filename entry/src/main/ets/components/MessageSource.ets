import { ChatMessage } from '../protocol/Wire';

export class MessageSource implements IDataSource {
  private rows: ChatMessage[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): ChatMessage { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((value: DataChangeListener) => value !== listener);
  }
  update(rows: ChatMessage[]): void {
    const previous = this.rows;
    this.rows = rows.slice();
    if (previous.some((row: ChatMessage, index: number) => row.id !== rows[index]?.id)) {
      this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
      return;
    }
    rows.forEach((row: ChatMessage, index: number) => {
      if (index >= previous.length) this.listeners.forEach((listener: DataChangeListener) => listener.onDataAdd(index));
      else if (row.text !== previous[index].text || row.streaming !== previous[index].streaming ||
        JSON.stringify(row.attachmentNames) !== JSON.stringify(previous[index].attachmentNames)) {
        this.listeners.forEach((listener: DataChangeListener) => listener.onDataChange(index));
      }
    });
  }
}
