# SmartTag Diagnostic for iPhone

Experimental native iPhone app for owner login, SmartTag selection, Bluetooth authentication and a discrete battery reading. UWB is outside this build. Samsung server acceptance and physical SmartTag interoperability remain unverified.

The interface follows account → tag → explicit scan → nearby peripheral selection → authenticate/read. No peripheral is selected automatically. Unsupported or incomplete credentials stop the test. Tokens and tag secrets stay on the phone and are excluded from diagnostic events.

## Build

See [build and signing instructions](docs/BUILD.md). The macOS workflow is prepared, not executed. It produces an **unsigned IPA requiring signing**. Windows cannot compile Swift or run the iOS Simulator.

## Account compatibility

The source-derived Samsung flow uses a registered `ms-app` redirect associated with the original Windows client. Samsung's acceptance of this return flow on iOS is unverified. The app reports failure without bypassing account ownership. No account or device was accessed while creating this project.

## Verification

Run `python scripts/verify_project.py` for portable configuration checks. Native validation requires `swift test` and the simulator checks in BUILD.md. Passing static checks does not establish a working Bluetooth handshake. See the protocol/account notes under `docs/`.

## Sources

Account and protocol research includes [uTag](https://github.com/KieronQuinn/uTag), licensed GPL-3.0. See LICENSE and THIRD_PARTY_NOTICES.md. This independent diagnostic is not a Samsung product.
