import Foundation

public enum AppleUWBVersion: Equatable {
    case v1
    case v2
}

/// These declarations describe an experiment, not recovered SmartTag capabilities.
public struct UWBAccessoryProfile {
    public let version: AppleUWBVersion
    public let accessoryAddress: UInt16
    public let manufacturerID: UInt32
    public let modelID: UInt32
    public let middlewareVersion: UInt32
    public let maximumClockDrift: UInt16
    public let requestedHopping: Bool

    public init(version: AppleUWBVersion, accessoryAddress: UInt16,
                manufacturerID: UInt32 = 0, modelID: UInt32 = 0,
                middlewareVersion: UInt32 = 0, maximumClockDrift: UInt16 = 20,
                requestedHopping: Bool = true) {
        self.version = version
        self.accessoryAddress = accessoryAddress
        self.manufacturerID = manufacturerID
        self.modelID = modelID
        self.middlewareVersion = middlewareVersion
        self.maximumClockDrift = maximumClockDrift
        self.requestedHopping = requestedHopping
    }
}

public struct AppleUWBParameters: Equatable {
    public let version: AppleUWBVersion
    public let sessionID: UInt32
    public let preamble: UInt8
    public let channel: UInt8
    public let slots: UInt16
    public let slotDurationRSTU: UInt16
    public let intervalMilliseconds: UInt16
    public let roundControl: UInt8
    public let stsIV: Data
    public let phoneAddress: UInt16
    public let maxClockDrift: UInt16
    public let hopping: Bool

    public init(version: AppleUWBVersion, sessionID: UInt32, preamble: UInt8,
                channel: UInt8, slots: UInt16, slotDurationRSTU: UInt16,
                intervalMilliseconds: UInt16, roundControl: UInt8, stsIV: Data,
                phoneAddress: UInt16, maxClockDrift: UInt16, hopping: Bool) {
        self.version = version
        self.sessionID = sessionID
        self.preamble = preamble
        self.channel = channel
        self.slots = slots
        self.slotDurationRSTU = slotDurationRSTU
        self.intervalMilliseconds = intervalMilliseconds
        self.roundControl = roundControl
        self.stsIV = stsIV
        self.phoneAddress = phoneAddress
        self.maxClockDrift = maxClockDrift
        self.hopping = hopping
    }
}

public enum AppleUWBProtocolError: Error {
    case invalidProfile
    case invalidConfiguration
    case unsupportedVersion
    case unsupportedRadioParameters
}

public enum AppleUWBProtocol {
    /// Accessory protocol R4 table 3-2, interoperability R3/R4 table 4-2.
    public static func accessoryData(profile: UWBAccessoryProfile) throws -> Data {
        guard validAddress(profile.accessoryAddress), profile.maximumClockDrift > 0,
              profile.version == .v2 || profile.requestedHopping else {
            throw AppleUWBProtocolError.invalidProfile
        }
        var inner: [UInt8] = []
        appendLE(profile.version == .v1 ? UInt16(1) : 2, to: &inner)
        appendLE(profile.version == .v1 ? UInt16(1) : 0, to: &inner)
        appendLE(profile.manufacturerID, to: &inner)
        appendLE(profile.modelID, to: &inner)
        appendLE(profile.middlewareVersion, to: &inner)
        inner.append(1) // Accessory controller/initiator; phone controlee/responder.
        appendLE(profile.accessoryAddress, to: &inner)
        appendLE(profile.maximumClockDrift, to: &inner)
        if profile.version == .v2 {
            inner.append(contentsOf: [0, 0, 0, 0])
            inner.append(profile.requestedHopping ? 1 : 0) // Request only; decode Apple's selection.
            appendLE(UInt16(6), to: &inner)
            appendLE(UInt16(2400), to: &inner)
            appendLE(UInt16(240), to: &inner)
        }
        var outer: [UInt8] = [1, 0, 0, 0, 0] // Outer 1.0; automatic update rate.
        outer.append(contentsOf: repeatElement(0, count: 10))
        outer.append(UInt8(inner.count))
        outer.append(contentsOf: inner)
        return Data(outer)
    }

    /// Only explicitly documented versions are decoded; no opaque data is guessed.
    public static func decodeShareable(_ data: Data) throws -> AppleUWBParameters {
        let bytes = [UInt8](data)
        guard bytes.count >= 5 else { throw AppleUWBProtocolError.invalidConfiguration }
        let version: AppleUWBVersion
        switch (u16(bytes, 0), u16(bytes, 2)) {
        case (1, 1): version = .v1
        case (2, 0): version = .v2
        default: throw AppleUWBProtocolError.unsupportedVersion
        }
        let expected = version == .v1 ? 30 : 35
        guard bytes.count == expected, Int(bytes[4]) == expected - 5 else {
            throw AppleUWBProtocolError.invalidConfiguration
        }
        if version == .v2 {
            guard bytes[30..<34].allSatisfy({ $0 == 0 }), bytes[34] <= 1 else {
                throw AppleUWBProtocolError.invalidConfiguration
            }
        }
        let slots = u16(bytes, 13)
        let slotDuration = u16(bytes, 15)
        let interval = u16(bytes, 17)
        let address = u16(bytes, 26)
        guard (9...12).contains(bytes[11]), bytes[12] == 9, slots >= 6,
              slotDuration >= 2400, slotDuration % 1200 == 0, interval > 0,
              validAddress(address) else {
            throw AppleUWBProtocolError.unsupportedRadioParameters
        }
        return AppleUWBParameters(version: version, sessionID: u32(bytes, 7),
            preamble: bytes[11], channel: bytes[12], slots: slots,
            slotDurationRSTU: slotDuration, intervalMilliseconds: interval,
            roundControl: bytes[19], stsIV: Data(bytes[20..<26]),
            phoneAddress: address, maxClockDrift: u16(bytes, 28),
            hopping: version == .v2 && bytes[34] == 1)
    }

    private static func validAddress(_ address: UInt16) -> Bool {
        address != 0 && address != 0xffff
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        for offset in 0..<MemoryLayout<T>.size {
            bytes.append(UInt8(truncatingIfNeeded: value >> (offset * 8)))
        }
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
}
