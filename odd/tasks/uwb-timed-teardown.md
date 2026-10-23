# Timed UWB teardown diagnostics

## Intent and authorized scope
User explicitly requested timer/close review, relative log timestamps, correction of demonstrated defects and new IPA2026-10-23. Existing MatyAlts gh session authorized for MatyAlts/SmartTagDiagnostic branch push/Actions/artifact retrieval. No PR/merge, no owner account/device requests. Baseline e4eb06a, source90e3218, prior GREEN39952971278:63core+31App+2UI=96native/12Python.

## Findings and decisions
Owner identified Base: NI timeout, stop ACK. Both-swapped: app30s timeout, stop ACK deadline expires. Both running callback/configACK/exactecho but0NIupdates. This is evidence of terminal/cleanup differences, not address correctness or radio compatibility.
Read-only delegated mapping found shared BLE timeout Task has no arm-ticket guard after sleep; canceled/resumed callbacks can affect replacement stages. BLE30s and NI30s independently race because NI starts via later UI callback. Stop3s starts before actual dispatch when another write pending. Fix scope is app lifecycle, no radio/default changes.
NI owns30s measurement deadline; BLE retains bounded35s fallback from configACK (5s margin, not more time promised to measure). Pending-write wait and dispatched STOP ACK each bounded3s independently, repeated stop must not extend. Token/generation/expiry guards prevent obsolete callbacks. Shared immutable monotonic log epoch across Bluetooth/NI, millisecond relative prefixes, explicit attempt/terminal/stop/close markers; buffers clear without independently resetting epoch. No raw private fields.

## Tasks and route
- [ ] C1: Add test-first deadline/stop/chronology coverage, implement guarded BLE timers, dispatched-stop budget and shared timestamps, correct terminal ordering. Delegated direct: mapping4+files and nontrivial multi-file writer trigger. Native baseline39958989027 in progress before source/test writes. Tests first observed RED required before production. Verify stale/canceled/early/duplicate/other-generation deadlines, both callback orderings, pending STOP/ACK deadlines, repeatedstop, common monotonic formatting/buffer reset, no fabricated distance. Preserve auth/battery/protocol/retry barriers.
- [ ] C2: Full native checks/archive, download verify unsigned arm64 IPA, capture/handoff. Parent remote orchestration; delegated fixes as needed. Observe tests/metadata/CRC/MachO/signature absence/SHA256. Real Cleo test pending owner.

## Workflow and constraints
Strict TDD ON by user AGENTS.md: native swift test/xcodebuild test macOS Actions. Windows lacks native runner; baseline then observed RED before production then GREEN. Python suite supplemental. RDD disabled/unmanaged. Apply work-unit-commits; cached ask-on-risk/stacked-to-main slices, no PR created. Forecast350-550 authored lines advisory; slice lifecycle behavior/timestamp behavior if needed, do not shrink code for budget. Rollback aftere4eb06a removes only this feature. Preserve untracked docs ZIP/JPG, including(3).zip. New tracker odd/tasks/uwb-timed-teardown.md mirror topic odd/uwb-timed-teardown/tasks project rea projects. Old closed tracker unchanged. Hardware/firmware cause unknown; no physical success claims.

## Verification and progress
Baseline remote39958989027 running at unchanged e4eb06a. Mapping delegated /root/timer_close_audit; writer will read this record before edits. No source writes yet.

- Baseline39958989027 complete SUCCESS at unchanged e4eb06a before tests. Tests-only temporary commitad39628 (10newApp cases) nativeRED39959874676 missing BLEOperationDeadline/related APIs observed before production. Delegated writer GO. Final workunit will combine tests+production afterGREEN; temporary commit remains test-first evidence only. No final IPA yet.
