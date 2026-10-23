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
- Next: delegate bounded writers with shared contracts; reconcile integration, run available verification, commit reviewable work units.

## Commit boundaries
Pending. Checkboxes close only with observed outcomes; pending native checks remain stated even when source delivery is complete.
