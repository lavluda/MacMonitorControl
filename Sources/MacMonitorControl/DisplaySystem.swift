import AppKit
import ApplicationServices
import CoreGraphics

struct DisplayMode: Identifiable {
    let value: CGDisplayMode

    var id: Int32 { value.ioDisplayModeID }
    var dimensions: String { "\(value.width) × \(value.height)" }
    var pixelDimensions: String { "\(value.pixelWidth) × \(value.pixelHeight)" }
    var isHiDPI: Bool { value.pixelWidth > value.width || value.pixelHeight > value.height }

    var refreshRate: String {
        value.refreshRate > 0 ? "\(value.refreshRate.formatted(.number.precision(.fractionLength(0...2)))) Hz" : "System refresh"
    }

    var title: String {
        let size = isHiDPI ? "\(dimensions) HiDPI" : dimensions
        return "\(size) · \(refreshRate)"
    }

    fileprivate var signature: ModeSignature {
        ModeSignature(
            width: value.width, height: value.height,
            pixelWidth: value.pixelWidth, pixelHeight: value.pixelHeight,
            refreshRate: value.refreshRate
        )
    }
}

private struct ModeSignature: Hashable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
}

struct Display: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let persistentID: String?
    let bounds: CGRect
    let isMain: Bool
    let isBuiltIn: Bool
    let mirrorSource: CGDirectDisplayID
    let currentMode: DisplayMode?

    var isMirrored: Bool { mirrorSource != kCGNullDirectDisplay }
}

struct DisplayTopology {
    let ids: Set<CGDirectDisplayID>
    private let verifiedUUIDs: [CGDirectDisplayID: String]

    init(_ displays: [Display]) {
        self.init(Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.persistentID) }))
    }

    init(_ identities: [CGDirectDisplayID: String?]) {
        ids = Set(identities.keys)
        let knownUUIDs = identities.compactMapValues { $0 }
        let counts = Dictionary(knownUUIDs.values.map { ($0, 1) }, uniquingKeysWith: +)
        verifiedUUIDs = knownUUIDs.filter { counts[$0.value] == 1 }
    }

    var isFullyVerified: Bool { verifiedUUIDs.count == ids.count }

    func matches(_ other: DisplayTopology) -> Bool {
        ids == other.ids && isFullyVerified && verifiedUUIDs == other.verifiedUUIDs
    }

    func verifiedIDs(in other: DisplayTopology) -> Set<CGDirectDisplayID> {
        Set(verifiedUUIDs.compactMap { id, uuid in other.verifiedUUIDs[id] == uuid ? id : nil })
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

enum DisplaySystem {
    @MainActor
    static func displays() -> [Display] {
        let screens = NSScreen.screens
        return onlineIDs().map { id in
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let name = screens.first { $0.displayID == id }?.localizedName
                ?? (isBuiltIn ? "Built-in Display" : "Display \(id)")
            return Display(
                id: id, name: name, persistentID: persistentID(for: id), bounds: CGDisplayBounds(id),
                isMain: CGDisplayIsMain(id) != 0, isBuiltIn: isBuiltIn,
                mirrorSource: CGDisplayMirrorsDisplay(id),
                currentMode: CGDisplayCopyDisplayMode(id).map(DisplayMode.init)
            )
        }
        .sorted {
            if $0.isMain != $1.isMain { return $0.isMain }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id < $1.id
        }
    }

    static func persistentID(for id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func onlineIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func modes(for display: Display) -> [DisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(display.id, options) as? [CGDisplayMode] ?? [])
            .filter { $0.isUsableForDesktopGUI() }
            .map(DisplayMode.init)
        var seen = Set<ModeSignature>()
        return ([display.currentMode].compactMap { $0 } + modes)
            .filter { seen.insert($0.signature).inserted }
            .sorted { lhs, rhs in
                let a = lhs.signature
                let b = rhs.signature
                return (a.width, a.height, a.pixelWidth, a.pixelHeight, a.refreshRate)
                    > (b.width, b.height, b.pixelWidth, b.pixelHeight, b.refreshRate)
            }
    }

    static func configure(
        _ scope: CGConfigureOption,
        _ changes: (CGDisplayConfigRef) -> CGError
    ) throws {
        var reference: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&reference)
        guard begin == .success, let reference else { throw DisplayChangeError.quartz(begin) }
        let result = changes(reference)
        guard result == .success else {
            CGCancelDisplayConfiguration(reference)
            throw DisplayChangeError.quartz(result)
        }
        let complete = CGCompleteDisplayConfiguration(reference, scope)
        guard complete == .success else { throw DisplayChangeError.quartz(complete) }
    }

    static func origin(_ point: CGPoint, display: CGDirectDisplayID, in config: CGDisplayConfigRef) -> CGError {
        CGConfigureDisplayOrigin(config, display, Int32(point.x), Int32(point.y))
    }
}

enum DisplayChangeError: LocalizedError {
    case quartz(CGError)
    case topologyChanged
    case unverifiedIdentity
    case arrangement

    var errorDescription: String? {
        switch self {
        case .quartz(let error): "macOS could not apply the display change (\(error.rawValue))."
        case .topologyChanged: "The connected displays changed. Try again with the current setup."
        case .unverifiedIdentity: "macOS did not provide a distinct identity for every display. Try configuring this setup in System Settings."
        case .arrangement: "That position would overlap or separate displays. Choose another position."
        }
    }
}

enum DisplayPosition: String, CaseIterable, Identifiable {
    case left = "Left", right = "Right", above = "Above", below = "Below"
    var id: Self { self }

    func origin(beside anchor: CGRect, size: CGSize) -> CGPoint {
        switch self {
        case .left: CGPoint(x: anchor.minX - size.width, y: anchor.minY)
        case .right: CGPoint(x: anchor.maxX, y: anchor.minY)
        case .above: CGPoint(x: anchor.minX, y: anchor.minY - size.height)
        case .below: CGPoint(x: anchor.minX, y: anchor.maxY)
        }
    }
}

enum DisplayLayout {
    static func diagram(_ frames: [CGDirectDisplayID: CGRect], in size: CGSize) -> [CGDirectDisplayID: CGRect] {
        let visible = frames.filter { !$0.value.isEmpty && !$0.value.isInfinite }
        let bounds = visible.values.reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isEmpty, size.width > 0, size.height > 0 else { return [:] }

        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let x = (size.width - bounds.width * scale) / 2
        let y = (size.height - bounds.height * scale) / 2
        return visible.mapValues { frame in
            CGRect(
                x: x + (frame.minX - bounds.minX) * scale,
                y: y + (frame.minY - bounds.minY) * scale,
                width: frame.width * scale,
                height: frame.height * scale
            ).insetBy(dx: min(2, frame.width * scale / 4), dy: min(2, frame.height * scale / 4))
        }
    }

    static func rebase(_ frames: [CGDirectDisplayID: CGRect], main: CGDirectDisplayID) -> [CGDirectDisplayID: CGPoint] {
        guard let origin = frames[main]?.origin else { return [:] }
        return frames.mapValues { CGPoint(x: $0.minX - origin.x, y: $0.minY - origin.y) }
    }

    static func origins(
        _ frames: [CGDirectDisplayID: CGRect],
        moving id: CGDirectDisplayID,
        beside anchor: CGDirectDisplayID,
        position: DisplayPosition,
        main: CGDirectDisplayID
    ) throws -> [CGDirectDisplayID: CGPoint] {
        guard id != anchor, let frame = frames[id], let reference = frames[anchor], frames[main] != nil else {
            throw DisplayChangeError.topologyChanged
        }
        var proposed = frames
        proposed[id] = CGRect(origin: position.origin(beside: reference, size: frame.size), size: frame.size)
        var connected: Set<CGDirectDisplayID> = [main]
        var pending = [main]
        while let next = pending.popLast(), let bounds = proposed[next] {
            for (other, candidate) in proposed where other != next {
                let intersection = bounds.intersection(candidate)
                if !intersection.isNull && !intersection.isEmpty { throw DisplayChangeError.arrangement }
                if touches(bounds, candidate), connected.insert(other).inserted {
                    pending.append(other)
                }
            }
        }
        guard connected.count == proposed.count else { throw DisplayChangeError.arrangement }
        return rebase(proposed, main: main)
    }

    private static func touches(_ a: CGRect, _ b: CGRect) -> Bool {
        let verticalOverlap = max(a.minY, b.minY) < min(a.maxY, b.maxY)
        let horizontalOverlap = max(a.minX, b.minX) < min(a.maxX, b.maxX)
        return (verticalOverlap && (a.maxX == b.minX || b.maxX == a.minX))
            || (horizontalOverlap && (a.maxY == b.minY || b.maxY == a.minY))
    }
}
