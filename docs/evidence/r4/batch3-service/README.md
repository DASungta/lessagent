# R4 batch 3: real service hardening and visual baseline

Date: 2026-11-17. Service: isolated T3 Code 0.1.9 at
`http://127.0.0.1:47893`, base directory `/tmp/t3-r4-accept-gHC0QI`.
No existing service, real work repository or real business task was used.

This batch fixes defects found after the second device batch and adds real
service and device readback. The signed HAP was installed over the dedicated
Huawei Mate 60 Pro (`ALN-AL80`, HDC `23E0224122000135`); after physical unlock,
model/message/queue/secret/attachment UI paths were exercised.

## Candidate

- `r4-batch3-candidate.hap`
- SHA256 `86b950e13afb6ac3b7a48226f8d6d570abf93706b8c4e84148e323f4d003092c`
- Signed build passed.
- Installed with `hdc install -r`; launch and core UI verification completed.
- Device bundle readback: versionName `0.1.1`, versionCode `2`,
  updateTime `2026-11-17T16:36:35.730Z`.
- Launch attempt returned `Error Code:10106102 The device screen is locked
  during the application launch, unlock screen failed`.

## Code changes

- First-send marker write failure now aborts before any request and is not
  reported as an unknown submission.
- A known first-send rejection clears the provisional recovery marker so a
  reconnect does not open a nonexistent thread; the intact draft stays editable.
- A successful launch transitions to the created thread before local draft
  cleanup; a cleanup failure cannot leave the same text ready to be sent again.
- Attendance/uploads now use the R4 limits (file 50 MiB, image 10 MiB) instead
  of the legacy 10 MiB file guard; cancellation destroys the actual HTTP upload.
- Attachments from another thread scope are rejected instead of silently
  dropped.
- Visible fork items retain `visibility`/`sourceThreadId`; inherited secret
  requests render read-only and cannot be answered through the fork.
- Secret URLs are limited to http(s), inherited requests are blocked in the
  client, references must use a configured provider, and direct values are
  trimmed before sending.
- Queue start is hidden while a run is active and rejected locally; the server
  otherwise refuses it. Resume uses the latest executed run (not array order)
  and only interrupted or usage-limit-failed runs.
- Guest pending messages have send/dismiss actions; guest sends use
  `queue_after_active`.
- Reasoning rows are visible; file sharing uses HarmonyOS `ShareKit` after a
  downloaded cache copy.
- A later session-settings failure keeps earlier successful setting changes
  visible and reports a partial result instead of pretending nothing changed.
- Draft resume checks environment identity and draft project scope before
  binding, preventing a stale account/environment draft from crossing scope.
- Clipboard context import uses the ArkUI `PasteButton` temporary authorization
  instead of a restricted `READ_PASTEBOARD` manifest grant (the latter made
  installation fail on the normal signing profile).
- Custom answers in multi-select questions submit as text, matching the original
  answer resolver instead of an array containing the typed text.
- Composer context (file/skill/terminal/clipboard) is isolated per
  environment+thread/draft key, so switching environments cannot carry a
  context record into the other composer. Expanded tool output can be attached
  as a typed `terminal` record.
- Subagent rows now surface a child thread's pending approval/input kind and
  keep the existing open/stop actions; inline child approval remains available
  after opening that child thread.

## Real service readback

- Queue: edit read back `QUEUE-EDITED`; reorder changed positions from
  `2/1` to `1/2`; promote removed the queued run and kept its message; cancel
  removed the queued run/message; start moved the run to `starting`; held
  queue changed `queueHeld=true` to `false` after `queue.resume`; direct steer
  persisted `STEER-R4-DIRECT`.
- Force stop: `outcome=released`, no shared threads, run became `interrupted`.
- Resume: interrupted run
  `run:thread:b2656cc7-48eb-4abd-8f1c-90e8c6fcc0b2:ordinal:1` created
  continuation `ordinal:2` in `starting`.
- Secret direct: request `saved`, assistant replied `SECRET-DIRECT-OK`; the
  dummy value was not present in the projection or evidence.
- Secret file delivery: request `saved`, agent read the private file and replied
  `SECRET-FILE-OK`.
- Secret decline: request `declined`, assistant replied `SECRET-DECLINED-ACK`.
- Secret inherited: a fork of an in-progress secret run is refused by the
  server (`running` runs cannot be forked), so the real inherited-pending case
  remains source/host verified rather than service-created.
- Attachments: one 70-byte PNG and one 12 MiB file were uploaded and attached
  to the same message; both `assets.createUrl` downloads returned HTTP 200 with
  exact byte counts. This proves the file >10 MiB path.
- Guest share: after enabling the beta flag on the isolated service only,
  `guestShare.create` returned `connect_unavailable`; no T3 Connect tunnel is
  configured. The disabled/error path is real; link creation is not.

## Original visual baseline

Real original mobile frames on Pixel 6 (`emulator-5554`) were added under
`docs/evidence/r4/original/`:

- `original-r4-send-menu.png`
- `original-r4-queue-badge.png`
- `original-r4-queue-sheet.png`
- `original-r4-approval.png`
- `original-r4-secret.png`

These are original-app frames against the same isolated service, not
source-inferred mockups. The comparison table is in
`docs/evidence/r4/original/README.md`.

## Checks

- `node --experimental-strip-types --test tests/*.test.mjs`: 208/208.
- `./scripts/build.sh`: success.
- No Git initialization, commit, push, publish or subagent.

## Remaining

- Launch and visually verify the installed batch 3 HAP on ALN-AL80 after
  physical unlock.
- Real M04 structured `request_user_input` requires a provider that exposes the
  tool; Codex Default in the isolated service does not.
- Secret provider/reference success requires a configured provider; the isolated
  service has an empty `secretProviders` map.
- Guest link creation requires a real T3 Connect tunnel/account.
- Usage-limit recovery needs a real provider usage-limit failure.
- History paging needs a service advertising `threadSnapshotPagination` and a
  thread above its page limit; this 0.1.9 service does not advertise it.
- Original maximum-font/dark/light/accessibility and pixel-level parity remain.

