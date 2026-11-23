import ServiceManagement
import SwiftUI

@main
struct MacMonitorControlApp: App {
    @StateObject private var model = DisplayModel()

    var body: some Scene {
        MenuBarExtra("Mac Monitor Control", systemImage: "display") {
            MonitorMenu(model: model)
                .onAppear { model.refresh() }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MonitorMenu: View {
    @ObservedObject var model: DisplayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var referenceID: CGDirectDisplayID?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var editingName = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private let accent = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark ? NSColor(srgbRed: 0.37, green: 0.84, blue: 0.76, alpha: 1)
                    : NSColor(srgbRed: 0.04, green: 0.38, blue: 0.35, alpha: 1)
    })
    private var isBusy: Bool { model.confirmationDeadline != nil || model.changingConnection }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.confirmationDeadline != nil { confirmation }
                    if model.changingConnection {
                        ProgressView("Updating display connection…")
                            .controlSize(.small)
                    }
                    if let error = model.error { errorNotice(error) }

                    if !model.extendedDisplays.isEmpty {
                        DisplayMap(displays: model.displays, selectedID: model.selectedID) { id in
                            model.selectedID = id
                        }
                        .disabled(isBusy)
                    }

                    if model.displays.isEmpty {
                        HStack {
                            Label("No active displays", systemImage: "display")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Refresh", action: model.refresh)
                        }
                    } else {
                        connectedDisplays.disabled(isBusy)
                    }

                    if !model.disconnectedDisplays.isEmpty {
                        disconnectedDisplays.disabled(isBusy)
                    }

                    if let display = model.selectedDisplay {
                        Divider()
                        displayDetails(display).disabled(isBusy)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: editingName)
            }
            .frame(maxHeight: 557)
            .fixedSize(horizontal: false, vertical: true)

            Divider()
            footer
        }
        .frame(width: 430)
        .background(.background)
        .tint(accent)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
        .onChange(of: model.selectedID) {
            editingName = false
            referenceID = nil
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "display")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mac Monitor Control")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(model.displays.count) active")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Identify", systemImage: "viewfinder", action: model.identify)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.extendedDisplays.isEmpty || isBusy)
                .help("Show each display’s number on its screen")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var connectedDisplays: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("Connected")
            ForEach(Array(model.displays.enumerated()), id: \.element.id) { index, display in
                let selected = display.id == model.selectedID
                Button {
                    model.selectedID = display.id
                } label: {
                    HStack(spacing: 10) {
                        displayNumber(index + 1, selected: selected)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name(for: display))
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text(displayDescription(display))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DisplayRowStyle(selected: selected, accent: accent))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var disconnectedDisplays: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Disconnected from Mac")
            ForEach(model.disconnectedDisplays) { display in
                HStack(spacing: 10) {
                    Image(systemName: "display")
                        .foregroundStyle(.secondary)
                        .frame(width: 23)
                        .accessibilityHidden(true)
                    Text(display.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    Spacer()
                    Button("Reconnect", systemImage: "arrow.clockwise") { model.reconnect(display) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Reconnect \(display.name)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
        }
    }

    private func displayDetails(_ display: Display) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Display settings")
                Spacer()
                if model.canRename(display) {
                    Button(editingName ? "Cancel" : "Rename", systemImage: editingName ? "xmark" : "pencil") {
                        name = model.alias(for: display)
                        editingName.toggle()
                        nameFocused = editingName
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }

            if editingName {
                HStack {
                    TextField("Display name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit { saveName(display) }
                    Button("Save") { saveName(display) }
                        .buttonStyle(.borderedProminent)
                }
                .transition(.opacity)
            }

            if display.isMirrored {
                Text("Adjust dimming and display mode on the mirror source.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                dimmingControl(display)
                if !model.modes.isEmpty { modeControl(display) }
            }

            let canArrange = model.displays.count > 1 && (!display.isMain || display.isMirrored)
            if !display.isBuiltIn || canArrange {
                HStack {
                    if canArrange { layoutControls(display) }
                    Spacer(minLength: 0)
                    if !display.isBuiltIn { disconnectControl(display) }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func displayNumber(_ value: Int, selected: Bool) -> some View {
        Text(value, format: .number)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(selected ? accent : Color.secondary)
            .frame(width: 24, height: 24)
            .background(selected ? accent.opacity(0.12) : Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel("Display \(value)")
    }

    private func dimmingControl(_ display: Display) -> some View {
        let amount = model.dimming[display.id, default: 0]
        let percentage = amount.formatted(.percent.precision(.fractionLength(0)))

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Software dimming")
                    .font(.callout.weight(.medium))
                Spacer()
                Text(percentage)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Slider(value: Binding(
                get: { model.dimming[display.id, default: 0] },
                set: { model.setDimming($0, display: display.id) }
            ), in: 0...0.75) {
                Text("Software dimming")
            }
            .labelsHidden()
            .accessibilityValue(percentage)
            .help(model.shortcutsEnabled
                  ? "Dims the image. Use ⌃⌥[ and ⌃⌥] to adjust all screens."
                  : "Dims the image using a screen overlay.")
        }
    }

    private func modeControl(_ display: Display) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "viewfinder.rectangular")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Display mode")
                    .font(.callout.weight(.medium))
                if let mode = display.currentMode, mode.isHiDPI {
                    Text("\(mode.pixelDimensions) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 10)
            Picker("Display mode", selection: Binding(
                get: { display.currentMode?.id },
                set: { id in
                    if let mode = model.modes.first(where: { $0.id == id }), id != display.currentMode?.id {
                        model.selectMode(mode, for: display)
                    }
                }
            )) {
                ForEach(model.modes) { mode in
                    Text(mode.title).tag(Optional(mode.id))
                }
            }
            .labelsHidden()
            .fixedSize()
            .help(display.currentMode.map { "\($0.dimensions) logical · \($0.pixelDimensions) pixels" }
                  ?? "Resolution, scaling and refresh rates reported by macOS")
        }
    }

    private func layoutControls(_ display: Display) -> some View {
        let references = model.extendedDisplays.filter { $0.id != display.id }
        let reference = references.first(where: { $0.id == referenceID }) ?? references.first

        return Menu("Layout", systemImage: "rectangle.2.swap") {
            if display.isMirrored {
                Button("Stop Mirroring") { model.mirror(display, source: nil) }
            } else if let reference {
                Button("Make Main Display") { model.makeMain(display) }
                Menu("Place Beside \(model.name(for: reference))") {
                    ForEach(DisplayPosition.allCases) { position in
                        Button(position.rawValue) { model.arrange(display, beside: reference, position: position) }
                    }
                }
                if references.count > 1 {
                    Menu("Reference Display") {
                        ForEach(references) { candidate in
                            Button(model.name(for: candidate)) { referenceID = candidate.id }
                        }
                    }
                }
                Menu("Mirror Display") {
                    ForEach(references) { candidate in
                        Button(model.name(for: candidate)) { model.mirror(display, source: candidate) }
                    }
                }
            }
        }
        .fixedSize()
        .controlSize(.small)
    }

    private func disconnectControl(_ display: Display) -> some View {
        let desktopIDs = Set(model.extendedDisplays.map(\.id))
        let canDisconnect = DisplayConnection.canDisconnect(display.id, desktopIDs: desktopIDs)
        let isAvailable = DisplayConnection.isAvailable
        let explanation = isAvailable
            ? "Keep another display active to disconnect this one."
            : "Display disconnect is unavailable on this version of macOS."

        return VStack(alignment: .trailing, spacing: 4) {
            Button("Disconnect from Mac", systemImage: "minus.circle") { model.disconnect(display) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isAvailable || !canDisconnect)
                .help("Remove this screen from the Mac desktop")
            if !isAvailable || !canDisconnect {
                Text(explanation).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func errorNotice(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark") { model.error = nil }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }

    private var footer: some View {
        HStack {
            Menu("Settings", systemImage: "gearshape") {
                Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                Toggle("Global Dimming Shortcuts", isOn: Binding(
                    get: { model.shortcutsEnabled }, set: model.setShortcutsEnabled
                ))
                Button("Reset Software Dimming", action: model.resetDimming)
                Divider()
                Button("Refresh Displays", action: model.refresh)
                Button("Open macOS Display Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
        .controlSize(.small)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var confirmation: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Keep display changes?").font(.callout.bold())
                if let deadline = model.confirmationDeadline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
                        Text("Reverting in \(remaining)s")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 4)
            Button("Revert", action: model.revert)
                .keyboardShortcut(.cancelAction)
            Button("Keep", action: model.keep)
                .buttonStyle(.borderedProminent)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }

    private func displayDescription(_ display: Display) -> String {
        if display.isMirrored {
            let source = model.displays.first { $0.id == display.mirrorSource }
            return source.map { "Mirroring \(model.name(for: $0))" } ?? "Mirrored display"
        }
        if display.isMain { return display.isBuiltIn ? "Main · Built-in" : "Main · External" }
        return display.isBuiltIn ? "Built-in display" : "External display"
    }

    private func saveName(_ display: Display) {
        model.rename(display, to: name)
        editingName = false
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            model.error = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct DisplayRowStyle: ButtonStyle {
    let selected: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected, accent: accent)
    }

    private struct Row: View {
        let configuration: Configuration
        let selected: Bool
        let accent: Color
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .opacity(enabled ? 1 : 0.62)
                .background {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(selected ? accent.opacity(configuration.isPressed ? 0.18 : 0.10)
                                       : Color.primary.opacity(enabled && hovering ? 0.06 : 0))
                }
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: selected)
        }
    }
}

private struct DisplayMap: View {
    let displays: [Display]
    let selectedID: CGDirectDisplayID?
    let select: (CGDirectDisplayID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let dark = Color(red: 0.08, green: 0.12, blue: 0.16)
    private let highlight = Color(red: 0.46, green: 0.89, blue: 0.82)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Desktop layout")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.76))

            GeometryReader { proxy in
                let frames = Dictionary(uniqueKeysWithValues: displays.filter { !$0.isMirrored }.map { ($0.id, $0.bounds) })
                let tiles = DisplayLayout.diagram(frames, in: proxy.size)
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    if let tile = tiles[display.id] {
                        screenTile(display, number: index + 1, tile: tile)
                    }
                }
            }
            .frame(height: 83)
            .accessibilityHidden(true)
        }
        .padding(12)
        .background {
            Canvas { context, size in
                var grid = Path()
                for x in stride(from: 0.0, through: size.width, by: 16) {
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0.0, through: size.height, by: 16) {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(.white.opacity(0.055)), lineWidth: 1)
            }
            .background(dark)
        }
        .clipShape(.rect(cornerRadius: 12))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedID)
    }

    private func screenTile(_ display: Display, number: Int, tile: CGRect) -> some View {
        let selected = display.id == selectedID
        let shape = RoundedRectangle(cornerRadius: 7)
        let foreground = selected ? highlight : Color.white.opacity(0.81)
        return Button {
            select(display.id)
        } label: {
            HStack(spacing: 5) {
                if tile.width > 50 && tile.height > 23 {
                    Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                        .font(.system(size: 13))
                }
                if tile.width > 17 && tile.height > 17 {
                    Text(number, format: .number)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
            }
            .foregroundStyle(foreground)
            .frame(width: tile.width, height: tile.height)
            .background(selected ? Color(red: 0.13, green: 0.33, blue: 0.33)
                                 : Color(red: 0.15, green: 0.20, blue: 0.25), in: shape)
            .overlay {
                shape.strokeBorder(selected ? highlight.opacity(0.9) : .white.opacity(0.25),
                                   lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help("Select display \(number)")
        .position(x: tile.midX, y: tile.midY)
    }
}
