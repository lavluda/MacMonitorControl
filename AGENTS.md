# Repository Guidelines

## Project Structure

MacMonitorControl is a new native macOS utility for managing built-in and external displays. Product research lives in `reports/` with supporting notes in `research_notes/`. The Xcode project is `MacMonitorControl.xcodeproj`. App code is in `Sources/MacMonitorControl/` and XCTest cases are in `Tests/MacMonitorControlTests/`.

## Build and Development

- Open `MacMonitorControl.xcodeproj` in Xcode and run the `MacMonitorControl` scheme. Click the display icon in the macOS menu bar.
- Run `xcodebuild -scheme MacMonitorControl -destination 'platform=macOS' build` to compile locally. Use `test` in place of `build` to run XCTest.
- Keep derived data on the Mac’s internal filesystem when building from an exFAT drive so AppleDouble files do not interfere with signing. The development target is macOS 14.

## Coding Conventions

Follow the surrounding code and Apple’s naming conventions for native code. Use names that distinguish hardware controls from software adjustments. For example, name a monitor backlight operation separately from a dimming overlay. Keep display detection and capability checks separate from menu presentation so both can be tested independently.

## Testing Guidelines

Record the Mac model, macOS version, display model, and connection path in hardware test results. Exercise disconnect and reconnect, sleep and wake, and multiple displays. Verify that unsupported controls are explained in the UI. For display mode and layout changes, verify that the user can recover if a setting makes a display unusable. Add automated coverage for capability handling and saved settings when the test target is available.

## Commits and Pull Requests

Use a short, descriptive commit subject. In pull requests, describe the behavior changed, how it was verified, and any hardware or operating system limits. Link the related issue when available. Include a screenshot or recording for visible changes and note which display setups were tested.

## Contributor Decisions

Ask before choosing an unresolved project direction, such as the minimum macOS version, distribution channel, or reliance on undocumented APIs.
