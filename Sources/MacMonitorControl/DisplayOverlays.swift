import AppKit

@MainActor
final class DisplayOverlays {
    private var dimmers: [CGDirectDisplayID: NSWindow] = [:]
    private var notices: [CGDirectDisplayID: NSWindow] = [:]
    private var noticeTimer: Task<Void, Never>?

    func updateDimming(_ levels: [CGDirectDisplayID: Double]) {
        let screens = NSScreen.screens
        for id in Array(dimmers.keys) where levels[id, default: 0] == 0 || !screens.contains(where: { $0.displayID == id }) {
            dimmers.removeValue(forKey: id)?.orderOut(nil)
        }
        for screen in screens {
            guard let id = screen.displayID, let level = levels[id], level > 0 else { continue }
            let window = dimmers[id] ?? makeWindow(frame: screen.frame, level: .mainMenu)
            window.setFrame(screen.frame, display: true)
            window.backgroundColor = .black
            window.alphaValue = level
            window.orderFrontRegardless()
            dimmers[id] = window
        }
    }

    func showNotices(_ messages: [CGDirectDisplayID: String]) {
        noticeTimer?.cancel()
        clearNotices()
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let message = messages[id] else { continue }

            let label = NSTextField(wrappingLabelWithString: message)
            label.font = .systemFont(ofSize: 23, weight: .semibold)
            label.textColor = .white
            label.alignment = .center
            label.preferredMaxLayoutWidth = min(480, screen.visibleFrame.width - 48)

            let size = label.fittingSize
            let frame = CGRect(
                x: screen.visibleFrame.midX - (size.width + 56) / 2,
                y: screen.visibleFrame.midY - (size.height + 32) / 2,
                width: size.width + 56, height: size.height + 32
            )
            let window = makeWindow(frame: frame, level: .statusBar)
            let backdrop = NSView(frame: CGRect(origin: .zero, size: frame.size))
            backdrop.wantsLayer = true
            backdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.84).cgColor
            backdrop.layer?.cornerRadius = 15
            label.frame = CGRect(x: 28, y: 16, width: size.width, height: size.height)
            backdrop.addSubview(label)
            window.contentView = backdrop
            window.orderFrontRegardless()
            notices[id] = window
        }
        noticeTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.clearNotices()
        }
    }

    private func clearNotices() {
        for window in notices.values { window.orderOut(nil) }
        notices.removeAll()
    }

    private func makeWindow(frame: CGRect, level: NSWindow.Level) -> NSWindow {
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = level
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return window
    }
}
