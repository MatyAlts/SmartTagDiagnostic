# iPhone SmartTag diagnostics

## Objective and authorized scope
Create an iPhone diagnostic app: owner-initiated Samsung browser login, selection of the owner's SmartTag, authenticated BLE connection, and battery read. Prepare (do not run) a macOS GitHub Actions build. No UWB ranging, Samsung requests, device access, publishing, workflow execution, or credentials are authorized in this implementation session.

## Context and constraints
Greenfield local repository; original APK/IPA remain outside it. Native SwiftUI, CoreBluetooth, AuthenticationServices, CryptoKit/CommonCrypto, Security Keychain; no third-party runtime dependencies. iPhone-only iOS 17+. Source research establishes protocol, not live interoperability. Account callback/server acceptance and tag-specific cipher must fail explicitly when incompatible; no simulated success. Tokens and master secrets stay local and are excluded from diagnostics, source and CI artifacts.

## Configuration
- TDD: strict, source: user-provided AGENTS.md. Runner: `swift test` (core) and `xcodebuild test` (app). Neither Swift nor Xcode is installed on this Windows host. Write XCTest before behavior; native RED/GREEN execution is pending macOS. Do not invent native evidence. Independent portable contract verification is supplemental.
- RDD: off by default (`gentle-ai review mode status` observed); disabled/unmanaged; no native review started.
- Governance: auth/security are critical; the user's explicit request authorizes implementing these named features, without live account/device operations.
- Delivery: ask-on-risk; forecast 2,000–3,000 authored lines; user selected stacked-to-main for future PRs. No remote PRs/push. Feature branch `feat/iphone-diagnostics`. Cohesive work-unit commits; record actual counts and boundaries below. Native compiler checks remain pending until an authorized macOS run.

## Tasks and routes
- [ ] T1: Implement validated credential model, KDF/AES, proof framing, counters, battery decoding, and BLE transport; tests and protocol documentation alongside. Route delegated direct: multiple nontrivial files, preparation trigger. Checks: deterministic vectors, malformed inputs, wrong proof, replay counters; hardware checks pending.
- [ ] T2: Implement owner browser login/PKCE/callback handling, token storage, V7 device metadata selection; tests and account-flow documentation alongside. Route delegated direct: multi-file auth implementation/research. Checks: state/URL validation, metadata variants, HTTP errors, secret-free logs, no live requests.
- [ ] T3: Implement native workflow UI, project generator, macOS CI and setup documentation; integrate and verify. Route delegated direct: multi-file UI/project/workflow. Checks: project/CI structure, portable contract checks; native build/XCTest/UI capture pending macOS, phone tests pending.

## Acceptance
User can start login, select an actual device, see missing/cipher metadata errors, connect by advertised identity (never an Android MAC on iOS), and run only auth/battery reads. Handshake uses correct phone/tag nonces, validates proof and lengths, disconnects on errors, waits for subscriptions/writes, times out. Cipher variants unsupported by implementation are blocked. Battery is a discrete state, not percent. CI builds an unsigned device IPA and simulator tests; signed distribution is documented separately and no credentials are embedded.

## Progress and evidence
- Explored workspace: only two supplied application archives, no existing repository/code. Created isolated project repository.
- Native runner absent; native tests and simulator visuals cannot be executed here.
- T1 source delivered and independently inspected: validated crypto, an authentication reducer with authored tests, explicit nearby selection, lazy Bluetooth initialization and battery read. Python hashlib KDF vectors and cryptography AES known answer passed. XCTest authored first; native RED/GREEN and tag checks pending.
- T2 source delivered: Samsung browser/PKCE flow, encrypted callback, Keychain, V7 metadata, refresh, URL/state validation, and logout-generation guards. Native account-crypto fixtures and negative metadata/URL tests authored. Live callback/server compatibility and native tests pending.
- T3 source delivered: native Spanish UI, generator, manual/PR macOS workflow, unsigned IPA packaging, simulator/app-unit test targets, setup/provenance/license docs. Portable configuration suite observed RED (missing verifier) then GREEN: 3/3; plist/reference checks and YAML parses passed. Static findings fixed; no visual/runtime approval claimed.
- Simulator/hardware and all Swift test execution are still pending; tasks above remain unchecked for these required verification outcomes. Source implementation is delivered.
- Source QA: all reported static integration fixes resolved, including explicit app-test package dependency. No native RDD run (disabled/unmanaged).
- App-bridge XCTest adds six PBKDF2/AES/callback/SPKI cases; total native test methods: 26 (not executed). UI fixture bypasses Keychain/network; Bluetooth is initialized only on explicit scan. Static fixes rechecked without claiming native validation.
- Final portable recheck passed: 3/3 Python tests, plist/reference validation, both YAMLs, design JSON, test-target/package wiring, manual/PR-only workflow and whitespace checks. The worktree was clean after source commits. No native execution, Simulator capture, account login or tag connection was performed.
- Next: publish only when authorized and run the prepared macOS workflow, sign the unsigned IPA, then validate login and physical authentication/battery. Source ZIP is provided separately from the original APK/IPA.

## Commit boundaries
- Bootstrap `2381a11`: isolated feature tracker; `main` points to this initial boundary, implementation stays on `feat/iphone-diagnostics`.
- T1 `cbe029a`: protocol + BLE + tests/docs, 529 authored lines. One cohesive local commit; for future stacked PRs the core (283 lines) and transport (246 lines) are natural review slices. No PR created, no size-only code shrinking; native tests pending.
- T2 `386caa1`: owner session, metadata, Keychain, tests and provenance; 577 authored lines plus 674-line verbatim upstream GPL license. A cohesive account unit exceeds the planning heuristic; future review can separate the pure account contracts from the iOS bridge, without shortening source/tests to fit. No PR created.
- T3 `8b2278a`: native UI, generator, app/unit/UI test wiring, CI, build/design documentation and recovery update; 550 authored additions/deletions. Natural future review slices: UI/project/native evidence versus CI/build tooling; no PR created.
- Running authored count of the three implementation commits: 1,656 (verbatim upstream LICENSE excluded); final recovery bookkeeping is separate. Delivery remains stacked-to-main when publishing is authorized, with no remote operations in this session.
- Rollback T1: remove protocol/core tests, BLE transport and protocol notes/manifest as a unit; no account data exists. Rollback T2: remove account core/bridge/tests and account notes; no live account data exists. Retain license/provenance for any remaining derived source.
- Rollback T3: remove app shell/project/workflow/config verification and surface records, retaining independently usable core source. Runtime checks remain pending rather than fabricated approvals.

## TDD cycle evidence
| Task | Test file | Layer | Safety net | RED | GREEN | Triangulation | Refactor |
|---|---|---|---|---|---|---|---|
| T1 | Tests/SmartTagCoreTests/ProtocolTests.swift | Core protocol | Greenfield; native runner unavailable | Authored first; native execution pending | Native pending; independent KDF/AES vectors passed | 11 methods, event-order/error cases authored | Static fixes; native rerun pending |
| T2 | Tests/SmartTagCoreTests/AuthTests.swift; Tests/AppTests/AccountSecurityTests.swift | Account contract and native bridge | Existing Swift tests could not run on Windows | Authored before behavior; bridge vectors added for existing helper | Native pending | 7 account + 6 crypto methods authored | Static source corrections; native rerun pending |
| T3 | scripts/test_verify_project.py; Tests/UITests/DiagnosticUITests.swift | Config and UI | No existing app | Portable missing-module RED observed; UI authored first | Portable 3/3; native pending | 3 config cases and 2 UI methods | Final portable recheck passed; UI pending |

## T4 — Public publication and native build (authorized 2026-10-22)
- User explicitly requests a public repository on their GitHub, upload of SmartTagDiagnostic and workflow execution to produce IPA. Destination: MatyAlts/SmartTagDiagnostic; credential: existing GitHub CLI session, matched to connected profile MatyAlts. This extends the previous local-only scope. Original APK/IPA and private Engram data remain excluded.
- [ ] T4: Publish initial source to the new repository default branch, dispatch macOS workflow, inspect native checks, fix build defects and retrieve unsigned IPA. Route: delegated readiness exploration (mapping/preparation); bounded delegates for nontrivial fixes, inline remote orchestration. Existing future PR chain preference retained; this initial direct publication is explicitly requested.
- Checks: public tracked-source readiness, matching account, successful native tests/archive, IPA artifact contents. Physical Samsung login/tag/UWB remain outside build verification.
- TDD: existing native tests run first in Actions; any failure recorded before correction. RDD remains disabled/unmanaged.
