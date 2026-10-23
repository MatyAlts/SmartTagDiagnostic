# Experimental UWB trial

## Apple configuration bridge

The trial uses public Nearby Interaction foreground accessory APIs. Its compatibility with SmartTag2 firmware is unproven. Configuration acceptance and Bluetooth write acknowledgements do not establish a distance measurement.

The [Apple accessory protocol R4](https://developer.apple.com/download/files/Nearby-Interaction-Accessory-Protocol-Specification-R4.pdf), section 3.4, defines the outer configuration header: version 1.0, preferred update rate 0 (automatic), ten reserved zero bytes, and the inner length. [Interoperability R3](https://developer.apple.com/download/files/Nearby-Interaction-with-UWB-Interoperability-Specification-R3.pdf), section 4, defines the version 1.1 inner configuration and generated output. The [R4 interoperability preview](https://developer.apple.com/download/files/Nearby-Interaction-with-UWB-Interoperability-Specification-Developer-Preview-R4.pdf) defines version 2.0 requests. The published tables were obtained from Apple's indexed document text; direct PDF retrieval returned 404 during research.

The experimental profile explicitly declares manufacturer/model/middleware IDs 0 and maximum clock drift 20 ppm. These are assumptions, not recovered SmartTag hardware values. It selects an accessory initiator/controller role and a fresh random short accessory address. Version 2 requests hopping, six slots, 2400 RSTU slot duration and 240 ms interval; Apple selects the final values. The wrapper totals 37 bytes for version 1.1 and 48 for version 2.0.

Generated data is decoded only for the documented version and exact length: 30 bytes for version 1.1 or 35 for version 2.0. The length byte excludes its five-byte header. Fields use little endian. Unknown versions, malformed lengths, reserved bytes, hopping values, and radio parameters outside the trial profile stop the experiment. The Samsung adapter performs additional profile checks before any transmission.

The version 2 input is gated by runtime support: [iOS 26.1 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_1-release-notes/) document additional accessory parameters including hopping. The integration uses the established `NINearbyAccessoryConfiguration(data:)` initializer rather than new SDK-only declarations.

Only a current, matching Nearby Interaction object's finite, nonnegative `distance` may be displayed in meters. RSSI, configuration acceptance, sample vectors and a previous session's values are never substitutes. The foreground trial requires the Nearby Interaction privacy description; no fabricated `com.apple.developer.nearby-interaction` entitlement is added.
