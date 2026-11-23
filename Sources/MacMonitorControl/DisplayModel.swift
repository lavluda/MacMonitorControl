import AppKit
import ApplicationServices
import Combine

@MainActor
final class DisplayModel: ObservableObject {
    @Published private(set) var displays: [Display] = []
    @Published private(set) var modes: [DisplayMode] = []
    @Published var selectedID: CGDirectDisplayID? {
        didSet { if selectedID != oldValue { reloadModes() } }
    }
    @Published private(set) var dimming: [CGDirectDisplayID: Double] = [:]
    @Published private(set) var confirmationDeadline: Date?
    @Published var error: String?
    @Published private(set) var shortcutsEnabled = false
    @Published private(set) var disconnectedDisplays: [DisconnectedDisplay] = []
    @Published private(set) var changingConnection = false
    @Published private var aliases = UserDefaults.standard.dictionary(forKey: "displayAliases") as? [String: String] ?? [:]

    struct DisconnectedDisplay: Identifiable {
        let id = UUID()
        let originalID: CGDirectDisplayID
        let name: String
        let identity: DisplayConnection.Identity
    }

    private struct Preview {
        let topology: DisplayTopology
        let before: [Display]
        let apply: (CGDisplayConfigRef) -> CGError
    }

    private let overlays = DisplayOverlays()
    private lazy var shortcuts = GlobalDimmingShortcuts { [weak self] amount in
        self?.changeDimmingForAll(by: amount)
    }
    private var observers = Set<AnyCancellable>()
    private var preview: Preview?
    private var revertTimer: Task<Void, Never>?
    private let dimmingLimit = 0.75

    var selectedDisplay: Display? { displays.first { $0.id == selectedID } }
    var extendedDisplays: [Display] { displays.filter { !$0.isMirrored } }

    init() {
        refresh()
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &observers)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &observers)
        if UserDefaults.standard.bool(forKey: "globalDimmingShortcuts") {
            setShortcutsEnabled(true)
        }
    }

    func refresh() {
        let previousIDs = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.persistentID) })
        displays = DisplaySystem.displays()
        let topology = DisplayTopology(displays)
        if !disconnectedDisplays.isEmpty, let candidates = try? DisplayConnection.registeredDisplays() {
            if !changingConnection {
                disconnectedDisplays.removeAll {
                    guard let id = $0.identity.resolve(in: candidates) else { return false }
                    return DisplayConnection.isConnected(id)
                }
            }
            let inactiveIDs = Set(disconnectedDisplays.compactMap { $0.identity.resolve(in: candidates) })
            displays.removeAll { inactiveIDs.contains($0.id) && !DisplayConnection.isConnected($0.id) }
        }
        if !displays.contains(where: { $0.id == selectedID }) {
            selectedID = displays.first?.id
        }
        reloadModes()
        dimming = dimming.filter { id, _ in
            displays.contains { $0.id == id && previousIDs[id] == .some($0.persistentID) }
        }
        updateDimming()

        if let preview, !topology.ids.isEmpty, !preview.topology.matches(topology) {
            revert()
            if error == nil { error = DisplayChangeError.topologyChanged.localizedDescription }
        }
    }

    func identify() {
        overlays.showNotices(Dictionary(uniqueKeysWithValues: displays.enumerated().compactMap { index, display in
            guard !display.isMirrored else { return nil }
            return (display.id, "\(index + 1)  \(name(for: display))")
        }))
    }

    func name(for display: Display) -> String {
        let alias = alias(for: display)
        return alias.isEmpty ? display.name : alias
    }

    func alias(for display: Display) -> String {
        aliasKey(for: display).flatMap { aliases[$0] } ?? ""
    }

    func canRename(_ display: Display) -> Bool { aliasKey(for: display) != nil }

    func rename(_ display: Display, to name: String) {
        guard let key = aliasKey(for: display) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        aliases[key] = trimmed.isEmpty ? nil : String(trimmed.prefix(64))
        UserDefaults.standard.set(aliases, forKey: "displayAliases")
    }

    func setShortcutsEnabled(_ enabled: Bool) {
        if enabled {
            guard shortcuts.register() else {
                error = "The dimming shortcuts are already in use or unavailable."
                return
            }
        } else {
            shortcuts.unregister()
        }
        shortcutsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "globalDimmingShortcuts")
    }

    func resetDimming() {
        dimming.removeAll()
        updateDimming()
    }

    private func updateDimming() {
        let extendedIDs = Set(extendedDisplays.map(\.id))
        overlays.updateDimming(dimming.filter { extendedIDs.contains($0.key) })
    }

    private func aliasKey(for display: Display) -> String? {
        guard let key = display.persistentID,
              displays.filter({ $0.persistentID == key }).count == 1 else { return nil }
        return key
    }

    func setDimming(_ amount: Double, display id: CGDirectDisplayID) {
        guard extendedDisplays.contains(where: { $0.id == id }) else { return }
        dimming[id] = min(max(amount, 0), dimmingLimit)
        updateDimming()
    }

    func changeDimmingForAll(by amount: Double) {
        guard !extendedDisplays.isEmpty else { return }
        var messages: [CGDirectDisplayID: String] = [:]
        for display in extendedDisplays {
            let level = min(max(dimming[display.id, default: 0] + amount, 0), dimmingLimit)
            dimming[display.id] = level
            messages[display.id] = "Software dimming  \(level.formatted(.percent.precision(.fractionLength(0))))"
        }
        updateDimming()
        overlays.showNotices(messages)
    }

    func selectMode(_ mode: DisplayMode, for display: Display) {
        startPreview(targets: [display]) { config in
            CGConfigureDisplayWithDisplayMode(config, display.id, mode.value, nil)
        }
    }

    func makeMain(_ display: Display) {
        let origins = DisplayLayout.rebase(frames, main: display.id)
        applyOrigins(origins, main: display.id, targets: [display])
    }

    func arrange(_ display: Display, beside anchor: Display, position: DisplayPosition) {
        do {
            let main = CGMainDisplayID()
            let origins = try DisplayLayout.origins(frames, moving: display.id, beside: anchor.id, position: position, main: main)
            applyOrigins(origins, main: main, targets: [display, anchor])
        } catch {
            self.error = error.localizedDescription
        }
    }

    func mirror(_ display: Display, source: Display?) {
        let targets = [display, source].compactMap { $0 }
        startPreview(targets: targets) { config in
            CGConfigureDisplayMirrorOfDisplay(config, display.id, source?.id ?? kCGNullDirectDisplay)
        }
    }

    func disconnect(_ display: Display) {
        let identity = DisplayConnection.Identity(id: display.id)
        guard let uuid = display.persistentID, identity.uuid == uuid else {
            error = ConnectionError.couldNotLocate.localizedDescription
            refresh()
            return
        }
        let device = DisconnectedDisplay(originalID: display.id, name: name(for: display), identity: identity)
        changeConnection(of: device, connected: false)
    }

    func reconnect(_ display: DisconnectedDisplay) {
        changeConnection(of: display, connected: true)
    }

    private func changeConnection(of display: DisconnectedDisplay, connected: Bool) {
        guard preview == nil, !changingConnection else { return }
        changingConnection = true
        error = nil

        Task {
            defer {
                changingConnection = false
                refresh()
            }

            do {
                try DisplayConnection.setConnected(
                    connected, identity: display.identity, expectedID: connected ? nil : display.originalID
                )
                if !connected { disconnectedDisplays.append(display) }

                for attempt in 0...8 {
                    let candidates = try DisplayConnection.registeredDisplays()
                    let currentID = display.identity.resolve(in: candidates)
                    if connected, let currentID, DisplayConnection.isConnected(currentID) {
                        disconnectedDisplays.removeAll { $0.id == display.id }
                        selectedID = currentID
                        return
                    }
                    if !connected, !DisplayConnection.isConnected(currentID ?? display.originalID) { return }
                    if attempt < 8 { try await Task.sleep(for: .milliseconds(250)) }
                }
                throw ConnectionError.stateUnchanged(connected: connected)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func keep() {
        guard let preview else { return }
        guard preview.topology.matches(DisplayTopology(DisplaySystem.displays())) else {
            revert()
            if error == nil { error = DisplayChangeError.topologyChanged.localizedDescription }
            return
        }
        do {
            try DisplaySystem.configure(.permanently, preview.apply)
            finishPreview()
            refresh()
        } catch {
            revert()
            if self.error == nil { self.error = error.localizedDescription }
        }
    }

    func revert() {
        guard let preview else { return }
        finishPreview()
        let verified = preview.topology.verifiedIDs(in: DisplayTopology(DisplaySystem.displays()))
        let previous = preview.before.filter { verified.contains($0.id) }
        let extended = previous.filter { !$0.isMirrored || !verified.contains($0.mirrorSource) }
        let main = extended.first(where: \.isMain) ?? extended.first
        let originalFrames = Dictionary(uniqueKeysWithValues: extended.map { ($0.id, $0.bounds) })
        let origins = main.map { DisplayLayout.rebase(originalFrames, main: $0.id) } ?? [:]
        guard !previous.isEmpty else { return }

        do {
            try DisplaySystem.configure(.forAppOnly) { config in
                for display in previous where CGDisplayMirrorsDisplay(display.id) != kCGNullDirectDisplay {
                    let result = CGConfigureDisplayMirrorOfDisplay(config, display.id, kCGNullDirectDisplay)
                    if result != .success { return result }
                }
                for display in extended {
                    guard let mode = display.currentMode else { continue }
                    let result = CGConfigureDisplayWithDisplayMode(config, display.id, mode.value, nil)
                    if result != .success { return result }
                }
                let arranged = Self.configureOrigins(origins, main: main?.id, config: config)
                if arranged != .success { return arranged }
                for display in previous where display.isMirrored && verified.contains(display.mirrorSource) {
                    let result = CGConfigureDisplayMirrorOfDisplay(config, display.id, display.mirrorSource)
                    if result != .success { return result }
                }
                return .success
            }
        } catch {
            self.error = "The preview could not be restored. Quit Mac Monitor Control to end its temporary configuration."
        }
        refresh()
    }

    private var frames: [CGDirectDisplayID: CGRect] {
        Dictionary(uniqueKeysWithValues: extendedDisplays.map { ($0.id, $0.bounds) })
    }

    private func reloadModes() {
        modes = selectedDisplay.map(DisplaySystem.modes(for:)) ?? []
    }

    private func applyOrigins(_ origins: [CGDirectDisplayID: CGPoint], main: CGDirectDisplayID, targets: [Display]) {
        guard !origins.isEmpty else { return }
        startPreview(targets: targets) { config in
            Self.configureOrigins(origins, main: main, config: config)
        }
    }

    private static func configureOrigins(
        _ origins: [CGDirectDisplayID: CGPoint], main: CGDirectDisplayID?, config: CGDisplayConfigRef
    ) -> CGError {
        for id in origins.keys.sorted() where id != main {
            guard let origin = origins[id] else { continue }
            let result = DisplaySystem.origin(origin, display: id, in: config)
            if result != .success { return result }
        }
        if let main, let origin = origins[main] {
            return DisplaySystem.origin(origin, display: main, in: config)
        }
        return .success
    }

    private func startPreview(targets: [Display], _ changes: @escaping (CGDisplayConfigRef) -> CGError) {
        guard preview == nil, !changingConnection else { return }
        error = nil
        let before = DisplaySystem.displays()
        let topology = DisplayTopology(before)
        guard topology.isFullyVerified else {
            error = DisplayChangeError.unverifiedIdentity.localizedDescription
            refresh()
            return
        }
        let targetTopology = DisplayTopology(targets)
        guard topology.matches(DisplayTopology(displays)),
              targetTopology.verifiedIDs(in: topology) == targetTopology.ids else {
            error = DisplayChangeError.topologyChanged.localizedDescription
            refresh()
            return
        }

        do {
            try DisplaySystem.configure(.forAppOnly, changes)
            preview = Preview(topology: topology, before: before, apply: changes)
            confirmationDeadline = Date().addingTimeInterval(15)
            revertTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.revert()
            }
            refresh()
        } catch {
            self.error = error.localizedDescription
            refresh()
        }
    }

    private func finishPreview() {
        revertTimer?.cancel()
        revertTimer = nil
        confirmationDeadline = nil
        preview = nil
    }
}
