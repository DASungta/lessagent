# Original mobile R4 visual baseline (real emulator)

Date: 2026-11-17. Captured from `com.t3tools.t3code.dev` on Pixel 6
(`emulator-5554`, Android 11) using the device session's `agent-device`.
The original app connected to the isolated T3 0.1.9 service through
`http://10.0.2.2:47893`.

Fixed source baseline: `DASungta/t3code`
`ad1b1365999c92c3fc7a054e7f3af84623f74fee`.

Screenshots:

- `original-r4-chats.png`: Chats home, bottom tabs, floating New thread.
- `original-r4-new-project.png`: New task project picker (`search projects`,
  `No project`, project rows).
- `original-r4-draft.png`: Thread draft hero, inline project/environment,
  checkout/branch controls, composer, model control and attachment button.
- `original-r4-model-sheet.png`: full-height model sheet with search/filter,
  provider group, current radio and favorites actions.
- `original-r4-thread2.png`: existing thread with header title/subtitle,
  folder/git/terminal icons, timestamps, grouped `Worked for …` activity,
  copy/action buttons and same composer.
- `original-r4-send-menu.png`: long-press send menu while a turn runs, with
  `Steer now` and `Queue` choices and their explanations.
- `original-r4-queue-badge.png`: live `Working … | 1 queued` capsule above the
  composer after choosing Queue.
- `original-r4-queue-sheet.png`: `Queued` sheet with the waiting text,
  `Send now`, row/remove affordance and close control.
- `original-r4-approval.png`: Codex shell approval card titled `APPROVAL
  NEEDED`, exact command, Decline / Allow session / Allow once.
- `original-r4-secret.png`: `Asking for a secret` card with reason, masked
  field, show-secret, save/decline and disabled submit until a value exists.

These are real original-app frames, not source-inferred mockups. The original
app's saved environment and a pairing route were used; no pairing code or
token is present in the retained frames.

## Comparison with current Harmony R4

| Surface | Original | Current Harmony | Status |
|---|---|---|---|
| Home | Bottom Chats/Pulls/Usage/Settings; floating New thread; search/filter in header | Sessions list with top compose icon and no bottom tabs | Partial, broader navigation remains R7 |
| Project picker | Modal `Choose project`, search, No project, project rows | Page `选择项目`, search, No project, project rows, drafts section | R4 entry/behavior matches; layout differs |
| Draft | “What should we build in …” hero; inline project/environment; checkout/branch controls; composer at bottom | “新任务” hero; environment/branch chips above list; model/context controls in composer; same local draft behavior | Functional; visual hierarchy and wording differ |
| Model settings | Full-height sheet, search/filter, provider groups, favorites, current radio | Full-height sheet with search, provider state and option descriptors, no favorites/filter/collapsible groups | Functional subset; visual/search completeness incomplete |
| Thread | Title/subtitle, folder/git/terminal header controls, worked-for groups, timestamps, per-message copy/actions | Title/subtitle and status, Worktree/Plan/Activity blocks, typed tool rows, timestamps/copy; folder/git/terminal deferred to R5/R6 | R4 message/activity core exists; visual hierarchy still differs |
| Composer | Same single composer, model label, attachment, queue/stop state | Single composer with model, context chips, attachments, queue/auto/steer | Core matches; visual density and queue control differ |
| Running send | Long-press send offers Steer now / Queue | Composer select exposes auto/queue/steer; queue action available while active | Behavior exists; original long-press discovery differs |
| Queue | Live capsule + `Queued` sheet with Send now/remove | Queue count pill + sheet with edit/move/start/promote/remove | Functional superset; visual grouping differs |
| Approval | Full-width card in feed; exact command; three actions | In-feed card with server options; same decisions | Functional core; layout not pixel-equal |
| Secret | Masked card, show/save/decline, reason and source affordances | Masked card with direct/reference modes; inherited pending disabled | Reference path implemented but not testable without configured provider |

This comparison does **not** close R4 visual acceptance. The remaining work is
pixel/interaction alignment for R4-specific controls, plus R5/R6 header
surfaces that the original thread page exposes.

## Paired R4 frames

The Harmony-side frames are the installed batch 2 captures; batch 3 was
installed but could not be launched while the Mate60Pro screen was locked.

| Original | Harmony |
|---|---|
| `original-r4-send-menu.png` | `../batch3-device/r4b3-queue-sheet.jpeg` |
| `original-r4-queue-badge.png` | `../batch3-device/r4b3-queue-badge.jpeg` |
| `original-r4-queue-sheet.png` | `../batch3-device/r4b3-queue-sheet.jpeg` |
| `original-r4-approval.png` | `../batch2-device/r4-codex-approval2.jpeg` |
| `original-r4-secret.png` | `../batch3-device/r4b3-secret-card.jpeg` |
