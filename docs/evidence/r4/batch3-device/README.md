# R4 batch 3 device UI evidence

Date: 2026-11-17. Device: HUAWEI Mate 60 Pro `ALN-AL80`, HDC
`23E0224122000135`. Service: isolated T3 Code 0.1.9 at
`127.0.0.1:47893`, base directory `/tmp/t3-r4-accept-gHC0QI`.

Installed candidate: `../batch3-service/r4-batch3-candidate.hap`, SHA256
`86b950e13afb6ac3b7a48226f8d6d570abf93706b8c4e84148e323f4d003092c`.
Device bundle readback: versionName `0.1.1`, versionCode `2`,
updateTime `2026-11-17T16:36:35.730Z`.

Screenshots contain only isolated test prompts and no secret value. The focused
password field made the system screenshot black (secure capture), so the secret
card is captured before focus and the successful save is proven by service
readback instead.

## Verified on device

- `r4b3-model-grouped.jpeg`: grouped Codex model rows, current model checkmark,
  search, save/cancel; the duplicate default sheet close icon no longer
  overlaps Save.
- `r4b3-thread-copy.jpeg`: messages show Copy even when no timestamp exists;
  empty manual-continuation user messages are hidden.
- `r4b3-queue-badge.jpeg`: live run shows `队列 · 1` in the composer.
- `r4b3-queue-sheet.jpeg`: queue sheet shows the waiting text and active-run
  actions; Start is hidden while a run is active.
- `r4b3-queue-edit.jpeg`: inline queue edit field with Cancel/Save.
- `r4b3-queue-removed.jpeg`: remove confirmation completed; queue count returned
  to 0.
- `r4b3-secret-card.jpeg`: secret request rendered with masked direct input,
  secure submit and decline. The typed dummy was submitted; the service read
  back `saved` for `HARMONY_SECRET` and the dummy value was not included in
  the projection/evidence.
- `r4b3-secret-saved-list.jpeg`: thread returned to the list with completed
  task state after the secret was consumed.
- `r4b3-attachment-preview.jpeg`: image attachment from a real message opens
  the native attachment panel with name, MIME, size, preview, save and share.
- `r4b3-attachment-share.jpeg`: HarmonyOS system share sheet opens with
  `r4-pixel.png` and its exact 70 B size.
- `r4b3-attachment-save.jpeg`: Document Save picker completed and the panel
  reported `已保存到所选位置`.
- `r4b3-dark-thread.jpeg`: the app under system dark mode uses dark canvas,
  surfaces, text and primary controls without white flashes.
- `r4b3-max-font-thread.jpeg`: captured after moving the system slider to
  maximum; the "larger font needs Care mode" dialog was cancelled and text
  bounds stayed identical, so this is retained as an inconclusive check, not a
  pass. Settings were restored to light/standard/standard.

## Service readback paired with UI

- Queue edit read back `HARMONY-QUEUE-1-EDITED` on the queued run.
- Queue remove left zero queued runs; the composer count/status updated.
- Secret direct submission from the Harmony card saved the request, then the
  Codex agent continued and completed the run.

## Still unverified on device

- Maximum-font check is inconclusive (Care mode flow not exercised);
  screen-reader, attachment picker from system Files and full original pixel
  comparison.
- The screenshot of the focused secure TextInput is intentionally black; only
  accessibility layout plus service readback prove the submitted value.

