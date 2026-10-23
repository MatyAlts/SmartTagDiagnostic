# Source attribution

This diagnostic is distributed under GNU GPL version 3; see [LICENSE](LICENSE).

Samsung account-flow and SmartTag protocol research and ported behavior derive from **uTag**, by Kieron Quinn and contributors, distributed under GPL-3.0:

- Repository: https://github.com/KieronQuinn/uTag
- Research revision: `f46375a9c2af6de4c8678f6aba7b91972054ae74`
- Account source: `app/src/main/java/com/kieronquinn/app/utag/repositories/AuthRepository.kt`
- Bluetooth source: `app/src/main/java/com/kieronquinn/app/utag/components/bluetooth/ConnectedTagConnection.kt`
- UWB research (not implemented here): `app/src/main/java/com/kieronquinn/app/utag/components/uwb/UwbConfig.kt`

Original copyright notices in upstream files remain applicable. This project contains a Swift adaptation and independent diagnostic interface, rather than the uTag Android application. The upstream GPL text is copied verbatim into LICENSE. SwiftUI, CoreBluetooth, AuthenticationServices, CryptoKit and Security are Apple platform frameworks; no third-party binary runtime is bundled.
