# R2 evidence

Baseline: `ad1b1365999c92c3fc7a054e7f3af84623f74fee`. Archive SHA256 is checked by `scripts/r2-contract-audit.mjs`.

## Artifacts

| File | Meaning |
|---|---|
| `r2-local-tests.log` | 153/153 host tests, including all 119 R1 tests |
| `r2-build.log` | Signed product HAP build, successful |
| `r2-candidate-signed.hap` | Product candidate, SHA256 `75fb05fdc3463b3c709cb884cf5e331a0180170a67215ce8f9b36df4f523755b` |
| `upstream-contract.json` | 14/14 fixed-upstream contract checks |
| `r2-upstream-contract.log` | Audit command output |
| `cloud-dpop-check-signed.hap` | Isolated CryptoFramework/Asset DPoP diagnostic HAP, SHA256 `fd0329ccd57342471a3092210a87b89a864eb0f4d67e34687a66f7d95802b586` |
| `r2-dpop-check-build.log` | Diagnostic HAP build output |
| `r2-source.tar.gz` | Source snapshot for this R2 delivery |
| `summary.json` | Machine-readable status and blockers |

## Evidence boundary

- No real Clerk request, relay request, environment link, device approval, or session was performed.
- The DPoP diagnostic HAP was built but **not installed or executed**. The authorized phone had the product app foreground and R1 work was active; replacing it was not necessary for local completion.
- No token, key, authorization code, pairing code, private URL, or real account data is stored here.
- `not-run` and external blockers are intentionally kept so R2 is not mistaken for accepted.
