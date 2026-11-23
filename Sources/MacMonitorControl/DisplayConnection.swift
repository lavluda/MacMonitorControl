import ApplicationServices
import Darwin

enum DisplayConnection {
    struct Identity {
        let uuid: String?
        let vendor: UInt32
        let model: UInt32
        let serial: UInt32

        init(id: CGDirectDisplayID) {
            self.init(
                uuid: DisplaySystem.persistentID(for: id),
                vendor: CGDisplayVendorNumber(id),
                model: CGDisplayModelNumber(id),
                serial: CGDisplaySerialNumber(id)
            )
        }

        init(uuid: String?, vendor: UInt32, model: UInt32, serial: UInt32) {
            self.uuid = uuid
            self.vendor = vendor
            self.model = model
            self.serial = serial
        }

        func resolve(in candidates: [CGDirectDisplayID: Identity]) -> CGDirectDisplayID? {
            if let uuid {
                let matches = candidates.filter { $0.value.uuid == uuid }
                if !matches.isEmpty { return matches.count == 1 ? matches.first?.key : nil }
            }

            guard vendor != 0, model != 0, serial != 0 else { return nil }
            let matches = candidates.filter {
                $0.value.vendor == vendor && $0.value.model == model && $0.value.serial == serial
            }
            return matches.count == 1 ? matches.first?.key : nil
        }
    }

    private typealias GetDisplayList = @convention(c) (
        UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?
    ) -> CGError
    private typealias ConfigureEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    private static let api: (list: GetDisplayList, configure: ConfigureEnabled)? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let list = dlsym(library, "CGSGetDisplayList"),
              let configure = dlsym(library, "CGSConfigureDisplayEnabled") else {
            dlclose(library)
            return nil
        }
        return (unsafeBitCast(list, to: GetDisplayList.self), unsafeBitCast(configure, to: ConfigureEnabled.self))
    }()

    static var isAvailable: Bool { api != nil }

    static func canDisconnect(_ id: CGDirectDisplayID, desktopIDs: Set<CGDirectDisplayID>) -> Bool {
        desktopIDs.contains { $0 != id }
    }

    static func isConnected(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayIsActive(id) != 0 || CGDisplayIsInMirrorSet(id) != 0
    }

    static func setConnected(_ connected: Bool, identity: Identity, expectedID: CGDirectDisplayID? = nil) throws {
        guard let api else { throw ConnectionError.unavailable }
        // Quartz's online list omits displays that have been disconnected in software.
        let candidates = try registeredDisplays()
        guard let id = identity.resolve(in: candidates), expectedID == nil || expectedID == id,
              CGDisplayIsBuiltin(id) == 0 else { throw ConnectionError.couldNotLocate }

        guard isConnected(id) != connected else { return }
        if !connected {
            let desktopIDs = Set(DisplaySystem.onlineIDs().filter {
                CGDisplayIsActive($0) != 0 && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay
            })
            guard canDisconnect(id, desktopIDs: desktopIDs) else { throw ConnectionError.lastDisplay }
        }

        try DisplaySystem.configure(.forAppOnly) { config in
            api.configure(config, id, connected)
        }
    }

    static func registeredDisplays() throws -> [CGDirectDisplayID: Identity] {
        guard let api else { throw ConnectionError.unavailable }
        var count: UInt32 = 0
        let queried = api.list(0, nil, &count)
        guard queried == .success else { throw DisplayChangeError.quartz(queried) }
        guard count > 0 else { return [:] }

        var ids = [CGDirectDisplayID](repeating: kCGNullDirectDisplay, count: Int(count))
        let read = api.list(count, &ids, &count)
        guard read == .success else { throw DisplayChangeError.quartz(read) }

        let uniqueIDs = Set(ids.prefix(Int(count))).subtracting([kCGNullDirectDisplay])
        return Dictionary(uniqueKeysWithValues: uniqueIDs.map { ($0, Identity(id: $0)) })
    }
}

enum ConnectionError: LocalizedError {
    case unavailable
    case couldNotLocate
    case lastDisplay
    case stateUnchanged(connected: Bool)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Display disconnect is unavailable on this version of macOS."
        case .couldNotLocate: "The Mac couldn’t identify this display. Check its input and HDMI cable, then try again."
        case .lastDisplay: "Connect another usable display before disconnecting this one."
        case .stateUnchanged(let connected):
            connected ? "The display hasn’t reconnected. Check its input and try again."
                : "The display is still connected to the Mac."
        }
    }
}
