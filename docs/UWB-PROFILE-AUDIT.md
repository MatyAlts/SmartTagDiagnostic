# UWB profile and activation audit

Audit date: 2026-10-23. Baseline: `54e6dea`; tracked work: U1 in
[`odd/tasks/uwb-profile-audit.md`](../odd/tasks/uwb-profile-audit.md).

The audit found no demonstrated missing activation command or role/header/vendor/IV
defect. It did find that the app's watchdog spends measurement time on setup.
Correcting that deadline does not establish the cause of the physical NI timeout.

## Observations and their limits

The owner observed an authenticated, decrypted 35-byte notification exactly equal
to the configuration sent during the same Cleo trial. NI subsequently reported
removal with reason `timeout`; no distance was observed. Equality establishes an
echo, not that firmware applied the radio settings or that UWB frames interoperated.
No packet capture or firmware trace was available for this audit.

The profile reported for that trial was channel 9, preamble 11, six slots,
2400 RSTU, 240 ms, round control 3 and hopping enabled. These are configuration
values, not measured over-air properties. Manufacturer/model/middleware zero and
20 ppm accessory clock drift remain experimental declarations, not recovered facts.

## Evidence and comparison

| Subject | Evidence | Conclusion / remaining uncertainty |
|---|---|---|
| Accessory role | Apple R3/R4 table 4-2 defines role 1 as initiator/controller. Bootstrap uses 1. uTag's phone is responder/controlee. | Roles are complementary; no demonstrated reversal. |
| Apple addresses | Apple `SOURCE_ADDRESS` and `DEST_ADDRESS` are `Uint16`, two octets; section 4.3.1 uses little endian. | Current numeric Apple decoding is supported. Samsung representation needs a separate check. |
| Samsung addresses | uTag copies the two address arrays into packet offsets 9 and 11 without conversion. | Its opaque Android arrays do not resolve Apple's numeric-to-Samsung mapping. |
| Session ID | Apple generates a session ID; current adapter decodes it numerically and writes Samsung's four-byte field. | No independent firmware evidence establishes the resulting interpretation. |
| Static STS vendor | Apple R3/R4 table 4-5 specifies `VENDOR_ID` default `0x004C`, UCI tag `0x27`. | This is a normative UWB default, not an inference from a company identifier. uTag's zero vendor differs. |
| Static STS IV | Apple output defines six bytes; current adapter copies them unchanged. | No evidence justifies reversing this array. Firmware acceptance remains unproven. |
| Header / PHY | Independent reconstruction of pinned uTag gives `00 2f 0c 9c 05` with hopping. | Source reproduction is verified; complete Apple PHY/MAC interoperability is not. |
| Slots / duration | Apple R4 requests at least six slots and slot duration at least 2400 RSTU, multiple of 1200. | Requested values fit; uTag's Android 2400 / Samsung 2000 pair remains an unexplained conversion. |
| Hopping | Apple R4 supplies a request and selected value; iOS 26.1 release notes mention support. | Hopping enabled is not an established iOS 27 incompatibility. |
| Foreground NI sequence | Public API starts NI, generates shareable configuration, sends it to the accessory, then supplies updates. | No additional public activate call or mandatory Samsung notification-processing step was identified. |

Apple input/output layouts and role meaning were checked against fresh indexed
official tables. The generated output does not carry a vendor field: the vendor
comes from Apple's specified default. A standards match does not establish that
the Samsung firmware accepts that vendor, IV or every generated parameter.

## Pinned Samsung source

The source reference is uTag commit
`f46375a9c2af6de4c8678f6aba7b91972054ae74`, not a moving branch:

- [UwbConfig.kt](https://github.com/KieronQuinn/uTag/blob/f46375a9c2af6de4c8678f6aba7b91972054ae74/app/src/main/java/com/kieronquinn/app/utag/components/uwb/UwbConfig.kt): packet packing, fixed fields and Android profile.
- The accompanying `LengthByteArray` short-array overload uses array copying;
  `getBytes` writes destination/tag address before local/phone address.
- Activation uses service FD5A, DEE30008 payload 01 followed by DEE30009
  configuration; stopping uses DEE30008 payload 00. The supplied APK's generic
  writer applies authenticated command encryption. See the bounded DEX locators
  and negative-search limitations in [UWB-SAMSUNG.md](UWB-SAMSUNG.md).

The DEX search did not recover the final separately delivered plugin's consumer.
It does not exclude reflection, ordinal dispatch or additional firmware behavior.

## App deadline defect and running evidence

At baseline, `NearbyInteractionClient.start` starts a 30-second watchdog before
`NISession.run`; sharing, encrypted BLE START/configuration and write ACKs consume
that budget. The experiment flow starts ranging only after the configuration ACK.
This is a demonstrable app-budget mismatch, independent of the physical cause.

Separate setup and post-ACK measurement deadlines, preserving cancellation and
attempt identity. Observe `sessionDidStartRunning` as a framework lifecycle event.
The prior technical log did not record that callback; its absence cannot establish
that NI never ran. Running, ACK and echo must never be promoted to distance.

## Controlled address-representation experiment

Keep Apple input/output numeric interpretation unchanged. Retain the current
Samsung encoding as default baseline; offer tag-only, phone-only and both swaps
as explicit experiments. Only Samsung bytes 9-12 may change for a fixed input.
Do not change session ID, vendor, IV, header, channel, preamble or timing together.
Reject invalid addresses and collisions after applying the selected representation.
Use asymmetric synthetic vectors; equal-byte addresses cannot distinguish modes.
Freeze the selection for each attempt and report only its category, never addresses.
Four timeouts would not establish which representation is correct.

## One premise challenge and acceptance

Matching FiRa parameters does not establish that SmartTag firmware emits Apple's
required controller MAC messages. The 35-byte exchange cannot prove that behavior.
Without a known-good independent implementation or over-air/firmware evidence,
the physical timeout cause remains unresolved. This does not prove impossibility.
Success remains a finite, nonnegative, current NI distance for the selected token.

## Apple references and access limitations

- [NINearbyAccessoryConfiguration](https://developer.apple.com/documentation/nearbyinteraction/ninearbyaccessoryconfiguration): current API documentation consulted through Context7 first.
- [Accessory protocol R4](https://developer.apple.com/download/files/Nearby-Interaction-Accessory-Protocol-Specification-R4.pdf): outer message structure.
- [Interoperability R3](https://developer.apple.com/download/files/Nearby-Interaction-with-UWB-Interoperability-Specification-R3.pdf): configuration version 1.1; sections 4.4-4.5.
- [Interoperability preview R4](https://developer.apple.com/download/files/Nearby-Interaction-with-UWB-Interoperability-Specification-Developer-Preview-R4.pdf): version 2.0; sections 3-4; indexed pages dated 2025-09-19.
- [iOS 26.1 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_1-release-notes/): additional UWB parameters including hopping.

Full PDF retrieval was unavailable: direct URLs failed and current download links
redirected to Apple login. Fresh indexed official excerpts support the cited tables;
they are not a complete revision-pinned PDF inspection or a complete PHY audit.
