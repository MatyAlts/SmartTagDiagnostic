# Product

An experimental, owner-operated iPhone diagnostic for a Galaxy SmartTag 2. The first supported goal is Samsung browser login, selection of the owner's tag, authenticated Bluetooth and a discrete battery reading. UWB is outside this build.

The user has an iPhone 17 Pro and a Galaxy S21. The app targets iPhone on iOS 17 or later. Account interoperability and hardware behavior remain unverified. Failed or unavailable steps must show an actionable error, never fabricated success.

The confirmed visual direction is conventional native iOS: account → tag → test, with a separate technical event screen. Use SwiftUI navigation, grouped lists, semantic colors, Dynamic Type and SF Symbols. No custom brand illustration or unofficial Samsung branding.

Secrets remain on the phone and are excluded from event text and exported build artifacts. Signing out clears account and Bluetooth state. Scanning, choosing a nearby peripheral and authenticating require distinct user actions.
