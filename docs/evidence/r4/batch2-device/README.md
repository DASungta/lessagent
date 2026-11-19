# R4 batch 2 device evidence

Date: 2026-11-17. Device: HUAWEI Mate 60 Pro `ALN-AL80`, HDC `23E0224122000135`.
Service: isolated T3 Code 0.1.9 at `127.0.0.1:47893`, base directory
`/tmp/t3-r4-accept-gHC0QI`. No existing service or real work repository was used.

Final candidate:

- `r4-batch2-candidate.hap`
- SHA256 `bfb1d6cb688ae4e6a54eaacc07fab50d63a0c6f2585e5d536038645f28a727d3`
- Installed over the dedicated device with `hdc install -r`.

Screenshots are cropped/full device frames. They contain test prompts only; no
pairing code, access token, secret value, or real business content.

## Real service/device checks

- `r4-connected2.jpeg`: isolated environment connected after manual address/code pairing.
- `r4-draft-resumed2.jpeg` and `r4-drafts-list.jpeg`: a local task draft survived
  force-stop/relaunch, appeared under Drafts, and reopened with its text.
- `r4-bpanel.jpeg`: branch/workspace picker loaded `main` from the isolated Git repo
  and exposed current-checkout vs new-worktree selection.
- `r4-worktree-done.jpeg`: a new worktree run completed; the server projection read
  back branch `t3/a6d686db` and path
  `/tmp/t3-r4-accept-gHC0QI/data/worktrees/work/t3-a6d686db-6907eca913f59f71`.
- `r4-sent3.jpeg`: first send used one launch, streamed the assistant response,
  rendered tool activity and returned the exact `R4-OK` reply.
- `r4-q1.jpeg`: while a run was active, a queued message was accepted and the
  composer showed `队列 · 1`.
- `r4-qpanel.jpeg`: queue sheet listed the waiting message with edit, promote,
  start, move and remove actions.
- `r4-codex-approval2.jpeg`: Codex approval card displayed the exact command and
  allow/deny actions.
- `r4-approved5.jpeg`: approval was resolved, the command ran, and the assistant
  returned `CODEX-DONE`; the server request row read back `resolved`.
- `r4-denied.jpeg`: denial read back `decision=decline`; the command did not run.
- `r4-sidechat.jpeg` and `r4-att-list.jpeg`: side chat fork was created with
  `lineage.sideChat=true` and relationship `fork`.
- `r4-sec12.jpeg`: structured secret request rendered with a password field,
  direct-input/reference affordance, secure submit and decline.

Attachment upload was also exercised against the isolated service with exact bytes:
`attachments.createUploadUrl` returned a signed path, the upload returned HTTP 204,
and the message projection read back a `file` attachment named `r4-test.txt`,
19 bytes, MIME `text/plain`. The same attachment was readable by the Codex session.

## Limits

- `r4-attach-menu.jpeg` and `r4-att-thread.jpeg` capture the attachment menu/open
  thread, not a completed picker selection from system Files.
- Queue edit/cancel/reorder/promote were exercised in host tests and rendered in
  the real queue sheet; a real server edit/cancel was not completed before the
  queued run started.
- Structured `request_user_input` was unavailable in the Codex provider's Default
  mode; the provider asked a plain-text fallback question instead.
- Secret reference/provider source selection is implemented, but no configured
  secret provider was available in the isolated environment.
- Guest share creation requires a running T3 Connect tunnel and was not available.
- Original Android mobile comparison could not be captured because the Pixel 6
  emulator was held by another device session; it was not interrupted.
- Usage-limit recovery, completed history paging, multi-attachment/media uploads
  and visual maximum-font/dark/light checks remain unverified.
