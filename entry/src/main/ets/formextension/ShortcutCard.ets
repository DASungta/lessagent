@Entry
@Component
struct ShortcutCard {
  build() {
    Column({ space: 6 }) {
      Text($r('app.string.app_name')).width('100%').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      FormLink({ action: 'router', moduleName: 'entry', abilityName: 'EntryAbility', params: { t3ShortcutAction: 'new-task' } }) {
        Text($r('app.string.shortcut_new_task')).width('100%').height(44).textAlign(TextAlign.Center)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_prominent')).backgroundColor($r('app.color.prominent')).borderRadius(12)
      }.width('100%')
      FormLink({ action: 'router', moduleName: 'entry', abilityName: 'EntryAbility', params: { t3ShortcutAction: 'sessions' } }) {
        Text($r('app.string.shortcut_sessions')).width('100%').height(44).textAlign(TextAlign.Center)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink')).backgroundColor($r('app.color.card')).borderRadius(12)
      }.width('100%')
    }.width('100%').height('100%').padding(12).justifyContent(FlexAlign.Center).backgroundColor($r('app.color.group'))
  }
}
