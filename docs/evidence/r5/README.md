# R5 evidence

2026-11-18. Baseline `ad1b1365999c92c3fc7a054e7f3af84623f74fee`; archive SHA256
`595b64affe9ae78510bbfdcd1cb4f282cade542aa4f8f7c704ea02998321e30a`.

| File | Meaning |
|---|---|
| `r5-local-tests.log` | 235/235 `node --experimental-strip-types --test tests/*.test.mjs` |
| `r5-final-build.log` | final signed `./scripts/build.sh` log |
| `r5-candidate-signed.hap` | signed candidate installed on Mate60Pro |
| `r5-hap.sha256` | candidate HAP SHA256 |
| `service-readback.json` | isolated T3 0.1.9 file/review/VCS/Git/pull request readback |
| `service-files-readback.json` | long-line/rename diff, binary read failure, workspace asset URL |
| `device/readback.json` | sanitized device actions/results and remaining blockers |
| `device/` | Mate60Pro screenshots, no credentials or message secrets |

Source and limits: [docs/r5-progress.md](../../r5-progress.md).

The isolated service returned no source-control providers, so no real PR was
created, commented, reviewed or merged. That remains an external test-repository
and account requirement; mock success is not recorded.

The old isolated lab under `/tmp` was cleaned by the host; port `47893` was then
taken by another session's new lab. Testing stopped there. The last dark-mode,
file-comment and Diff-navigation screenshots were lost with `/tmp`; their
structured results remain in `device/readback.json`.
