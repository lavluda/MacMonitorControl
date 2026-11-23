import CoreGraphics
import XCTest
@testable import MacMonitorControl

final class DisplayLayoutTests: XCTestCase {
    private let frames: [CGDirectDisplayID: CGRect] = [
        10: CGRect(x: 0, y: 0, width: 1800, height: 1000),
        20: CGRect(x: 1800, y: 0, width: 1200, height: 800),
        30: CGRect(x: 3000, y: 0, width: 1600, height: 900)
    ]

    @MainActor
    func testReadsCurrentDisplayModeFromWindowServer() throws {
        let displays = DisplaySystem.displays()
        guard !displays.isEmpty else { throw XCTSkip("No display session is available.") }
        let main = try XCTUnwrap(displays.first(where: \.isMain))
        let current = try XCTUnwrap(main.currentMode)
        XCTAssertGreaterThan(current.value.pixelWidth, 0)
        XCTAssertTrue(DisplaySystem.modes(for: main).contains { $0.id == current.id })
    }

    func testDiagramCentersLayoutAndPreservesDisplayPositions() throws {
        let source: [CGDirectDisplayID: CGRect] = [
            10: CGRect(x: -100, y: 0, width: 100, height: 60),
            20: CGRect(x: 0, y: -100, width: 60, height: 100)
        ]
        let tiles = DisplayLayout.diagram(source, in: CGSize(width: 320, height: 160))
        let left = try XCTUnwrap(tiles[10])
        let top = try XCTUnwrap(tiles[20])

        XCTAssertLessThan(left.maxX, top.minX)
        XCTAssertLessThan(top.maxY, left.minY)
        XCTAssertEqual(left.union(top).midX, 160, accuracy: 0.001)
        XCTAssertEqual(left.union(top).midY, 80, accuracy: 0.001)
        XCTAssertTrue(DisplayLayout.diagram([10: .zero], in: CGSize(width: 320, height: 160)).isEmpty)
    }

    func testChangingMainKeepsRelativePositions() {
        let origins = DisplayLayout.rebase(frames, main: 20)
        XCTAssertEqual(origins[10], CGPoint(x: -1800, y: 0))
        XCTAssertEqual(origins[20], .zero)
        XCTAssertEqual(origins[30], CGPoint(x: 1200, y: 0))
    }

    func testPlacesDisplayAboveReference() throws {
        let origins = try DisplayLayout.origins(frames, moving: 30, beside: 10, position: .above, main: 10)
        XCTAssertEqual(origins[30], CGPoint(x: 0, y: -900))
        XCTAssertEqual(origins[20], frames[20]?.origin)
    }

    func testRejectsOverlappingScreens() {
        XCTAssertThrowsError(try DisplayLayout.origins(frames, moving: 30, beside: 10, position: .right, main: 10))
    }

    func testRejectsMovingBridgeScreen() {
        XCTAssertThrowsError(try DisplayLayout.origins(frames, moving: 20, beside: 10, position: .left, main: 10))
    }
}


final class DisplayConnectionTests: XCTestCase {
    func testLastIndependentDisplayCannotBeDisconnected() {
        XCTAssertFalse(DisplayConnection.canDisconnect(10, desktopIDs: [10]))
        XCTAssertFalse(DisplayConnection.canDisconnect(10, desktopIDs: []))
        XCTAssertTrue(DisplayConnection.canDisconnect(10, desktopIDs: [10, 20]))
    }

    func testReconnectUsesCurrentIDEvenIfOriginalIDWasReused() {
        let display = DisplayConnection.Identity(uuid: "target", vendor: 10, model: 20, serial: 30)
        let replacement = DisplayConnection.Identity(uuid: "replacement", vendor: 10, model: 20, serial: 30)
        XCTAssertEqual(display.resolve(in: [1: replacement, 2: display]), 2)
        XCTAssertNil(display.resolve(in: [2: display, 3: display]))
    }

    func testReconnectFallsBackToUniqueEDIDSerial() {
        let saved = DisplayConnection.Identity(uuid: "before", vendor: 10, model: 20, serial: 30)
        let changed = DisplayConnection.Identity(uuid: "after", vendor: 10, model: 20, serial: 30)
        let noSerial = DisplayConnection.Identity(uuid: nil, vendor: 10, model: 20, serial: 0)

        XCTAssertEqual(saved.resolve(in: [3: changed]), 3)
        XCTAssertNil(saved.resolve(in: [3: changed, 4: changed]))
        XCTAssertNil(noSerial.resolve(in: [3: noSerial]))
    }

    func testWindowServerListContainsOnlineDisplays() throws {
        guard DisplayConnection.isAvailable else { throw XCTSkip("Display disconnect is unavailable.") }
        let online = DisplaySystem.onlineIDs()
        guard !online.isEmpty else { throw XCTSkip("No display session is available.") }
        let candidates = try DisplayConnection.registeredDisplays()
        XCTAssertTrue(online.allSatisfy { candidates[$0] != nil })
    }
}


final class DisplayTopologyTests: XCTestCase {
    func testMatchingRuntimeIDsRequireSameMonitorUUIDs() {
        let before = DisplayTopology([1: "built-in", 2: "original"])
        let replaced = DisplayTopology([1: "built-in", 2: "replacement"])

        XCTAssertTrue(before.matches(before))
        XCTAssertFalse(before.matches(replaced))
        XCTAssertEqual(before.verifiedIDs(in: replaced), [1])
    }

    func testReenumeratedMonitorsAreNotTargetsForSavedTransactions() {
        let before = DisplayTopology([1: "built-in", 2: "external"])
        let reenumerated = DisplayTopology([1: "built-in", 3: "external"])

        XCTAssertFalse(before.matches(reenumerated))
        XCTAssertEqual(before.verifiedIDs(in: reenumerated), [1])
    }

    func testMissingAndDuplicateUUIDsAreExcludedFromRestoration() {
        let before = DisplayTopology([1: "built-in", 2: "external", 3: nil])
        let ambiguous = DisplayTopology([1: "built-in", 2: "external", 3: "external"])

        XCTAssertFalse(before.matches(before))
        XCTAssertFalse(ambiguous.matches(ambiguous))
        XCTAssertEqual(before.verifiedIDs(in: ambiguous), [1])
    }
}
