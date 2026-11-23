# Native macOS display controls and hardware validation

## What macOS already provides

### Takeaway

Apple's Displays settings are the baseline for display configuration. A menu-bar utility adds faster access and reliable per-display workflows across supported hardware.

### Cited Findings

- Displays settings cover resolution, arrangement, selecting the main display, mirroring or extending the desktop, detection, supported brightness and automatic brightness, True Tone, color profiles, calibration, reference presets, supported rotation, refresh rate, Adaptive Sync, HDR, Night Shift, and some device-specific options. Availability varies by Mac and display. [Apple Displays settings](https://support.apple.com/en-ie/guide/mac-help/mh40768/mac)
- Native external monitor count, refresh rate, and resolution vary with Mac model, display, cable, adapter and the modes used by other connected displays. Closed-lid use may need external power, keyboard and mouse. An Apple silicon laptop may also require accessory approval. [Apple troubleshooting guidance](https://support.apple.com/en-us/102501)
- Scaling above a screen's native resolution can affect refresh rate and HDR availability. [Apple MacBook Pro display guide](https://support.apple.com/guide/macbook-pro/connect-an-external-display-apd8cdd74f57/mac)
- Apple advises waiting 15 seconds after an unsupported resolution blanks the display, then pressing Escape if necessary. That behavior is documented for the system workflow. [Apple resolution guide](https://support.apple.com/en-us/guide/mac-help/mchl86d72b76/mac)

### Inferences

- Show the mode choices available now, including apparent size, backing pixels, and refresh rate. Refresh the list after changes to hardware or topology. Implement a confirmation timer and explicit rollback for programmatic changes as an app requirement.

### Gaps

- Whether specific monitor features appear in macOS can only be established for the target combinations of Macs, OS builds, monitors, cables, and docks.

## Which features have a documented native API

### Takeaway

Public frameworks cover much of the display-management core. Monitor controls, host virtual displays, and system-level overrides are separate feasibility tracks.

### Cited Findings

- Native shell: SwiftUI MenuBarExtra and AppKit screen notifications. ServiceManagement's SMAppService.mainApp supports opt-in launch at login on macOS 13 or later. [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) · [Display change notification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification) · [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- Quartz Display Services exposes display enumeration and configuration callbacks, mode enumeration and selection, arrangement through display origins, and system mirroring. Setting an origin of (0,0) makes a display the main display. Public transactions cover multiple changes and can persist for app lifetime, login session, or permanently. CGDisplayMode has separate logical and pixel dimension accessors and a refresh-rate accessor. [Quartz Display Services](https://developer.apple.com/documentation/CoreGraphics/quartz-display-services) · [Quartz overview](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/QuartzDisplayServicesConceptual/Articles/Overview.html) · [Configuration transactions](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/QuartzDisplayServicesConceptual/Articles/DisplayTransactions.html) · [Session scope](https://developer.apple.com/documentation/coregraphics/cgconfigureoption/forsession) · [Mode fields](https://developer.apple.com/documentation/coregraphics/cgdisplaymode?language=objc)
- Apple documents a display UUID mapping API and display serial-number queries. A utility developer reports ambiguity with identical monitor firmware and dock-dependent routing, so a display ID or monitor name alone is a weak profile key. [ApplicationServices functions](https://developer.apple.com/documentation/applicationservices/applicationservices_functions) · [Core Graphics functions](https://developer.apple.com/documentation/coregraphics/core-graphics-functions?changes=_8_6) · [Lunar FAQ](https://lunar.fyi/faq)
- ColorSync documents working with device ICC profiles. AppKit's NSScreen exposes current, potential, and reference EDR headroom. Those APIs support profile management and diagnostics respectively. The public EDR properties report values, and Metal's documented EDR path adjusts content rendered by the app. [ColorSync device profiles](https://developer.apple.com/documentation/colorsync/colorsyncdevicesetcustomprofiles%28_%3A_%3A_%3A%29?language=objc) · [NSScreen EDR](https://developer.apple.com/documentation/appkit/nsscreen/maximumextendeddynamicrangecolorcomponentvalue?changes=l_6) · [Apple tone mapping guide](https://developer.apple.com/documentation/metal/performing-your-own-tone-mapping)
- Core Audio HAL supports audio-device introspection and checking whether properties are settable. Some display audio outputs lack a settable volume. Monitor speaker control via DDC is a separate path. [AudioHardwareSystem](https://developer.apple.com/documentation/coreaudio/audiohardwaresystem?changes=_10) · [AudioHardwareObject](https://developer.apple.com/documentation/coreaudio/audiohardwareobject) · [Apple volume Q&A](https://developer.apple.com/library/archive/qa/qa1016/) · [MonitorControl](https://github.com/MonitorControl/MonitorControl)
- Hardware DDC/CI controls can include brightness, contrast, speaker volume, mute and input select on supported monitors and paths. Hardware, gamma and overlay controls have different effects. Lunar documents HDR trouble when using the gamma API. Apple Silicon hardware DDC and Apple native brightness merit early prototypes. BrightSync identifies its IOAVService I²C and DisplayServices brightness APIs as private. [MonitorControl](https://github.com/MonitorControl/MonitorControl) · [BetterDisplay DDC examples and capability detection](https://betterdisplay.pro/guide/integration/cli-reference/) · [BrightSync implementation notes](https://github.com/pszypowicz/brightsync) · [Lunar HDR FAQ](https://lunar.fyi/faq)
- DisplayLink Manager is a different path from direct DDC. Synaptics documents a brightness and contrast UI with DDC-capable displays, Manager 1.12.1+, and Ventura+, with a USB-C-to-HDMI cable exception. BetterDisplay's experimental Manager command relay is off by default and depends on compatible hardware and software. Synaptics separately requires Screen Recording permission for Manager's display rendering. MonitorControl's direct-path restrictions can coexist with these Manager features. [Synaptics brightness and contrast support](https://support.displaylink.com/knowledgebase/articles/2021015-brightness-and-contrast-control-settings) · [BetterDisplay DisplayLink controller](https://betterdisplay.pro/guide/interface-reference/settings/displays/display/device-control/displaylink/) · [DisplayLink first-time configuration](https://support.displaylink.com/knowledgebase/articles/2024872-displaylink-manager-first-time-configuration)
- ScreenCaptureKit is public for recording or streaming existing displays, apps and windows, with user permission. DeskPad creates host virtual desktops with CGVirtualDisplay, an API declared in its own private header. Apple's similarly named VZMacGraphicsDisplayConfiguration is for virtual machines. [Apple ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) · [DeskPad implementation](https://github.com/Stengo/DeskPad/blob/main/DeskPad/Frontend/Screen/ScreenViewController.swift) · [DeskPad private header references](https://github.com/Stengo/DeskPad/pull/67/files) · [Apple Virtualization](https://developer.apple.com/documentation/virtualization/vzmacgraphicsdisplayconfiguration?changes=_6)
- BetterDisplay's physical-display flexible scaling uses system configuration overrides with helper or administrator authorization and possible reactivation/reboot. Native mode selection and creating new HiDPI modes are different engineering tasks. Lunar discloses a hidden API for true disconnect on Apple silicon and a brightness/gamma/mirroring emulation on Intel. [BetterDisplay system configuration](https://betterdisplay.pro/guide/interface-reference/settings/displays/display/system-configuration/) · [Lunar FAQ](https://lunar.fyi/faq)
- Input Monitoring governs global keyboard/mouse monitoring. Accessibility permission controls trusted accessibility clients. Some competitors request it for media keys or app-aware triggers. Capture permission is distinct. [Apple Input Monitoring](https://support.apple.com/en-bn/guide/mac-help/mchl4cedafb6/mac) · [Apple Accessibility](https://support.apple.com/en-ie/guide/mac-help/mh43185/27/mac/27) · [Lunar permissions](https://lunar.fyi/faq)

### Inferences

- Keep a SwiftUI/AppKit shell and a documented Quartz backend for topology, mode lists, mode changes, arrangement, and mirror groups. Keep monitor hardware commands, any native brightness adapter, and experimental OS integrations isolated behind capability checks. Use software dimming as a clearly labeled fallback and independently test SDR/HDR and overlay behavior before defaulting to gamma on any setup.
- Detect support for each command and connection, rather than assuming a brightness-capable path also supports volume, input, or power. Distinguish hardware brightness from image dimming, true disconnect from black overlay and standby, and device speaker volume from macOS output volume.
- Capture should be opt-in for preview, capture, and streaming. Test the chosen keyboard implementation before setting permission requirements. Offer an in-app/manual path after permission denial and keep unrelated controls available.
- Plan profiles to handle multiple indistinguishable monitors, port moves, disconnect/reconnect races, topology changes, and selecting the wrong device. Prefer an ambiguous-state prompt over guessing. Use local preferences and optional redacted diagnostic export.

### Gaps

- This review did not identify public APIs that cover general-purpose host virtual-display creation, arbitrary new physical timings and HiDPI overrides, driver-independent DDC or native backlight writes, system-wide HDR state and XDR brightness upscaling, true per-display disconnect, or universal programmatic rotation. Consider these a platform investigation rather than claiming public support or claiming no solution exists.
- Core Graphics public/sandbox behavior for mode, layout, and ColorSync writes needs verification in a signed sandboxed build. No guarantee of identifier stability across all topology changes was established.

## How should the project choose distribution and prove support

### Takeaway

Decide the release channel before private APIs or privileged helpers become central to the app. Validate compatibility per operation on physical hardware.

### Cited Findings

- Apple requires appropriately sandboxed Mac App Store builds, public API use, and no requests for root privilege escalation under its App Review Guidelines, among other requirements. Approval depends on the actual implementation. [App Review Guidelines 2.4.5 and 2.5.1](https://developer.apple.com/app-store/review/guidelines/)
- Developer ID direct distribution uses Gatekeeper signing and Apple notarization. Apple lists Developer ID credentials and Hardened Runtime among notarization requirements. Notarization scans a distributed binary and does not establish API compatibility across macOS upgrades. [Developer ID signing](https://developer.apple.com/developer-id/) · [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/)
- Direct vs docked cables, SDR vs HDR, and monitor OSD/readback are discrete validation factors. A recognized controller or a working image does not establish hardware-command compatibility. [BetterDisplay dock guide](https://betterdisplay.pro/guide/tutorials/hardware-brightness-and-volume-through-dock/) · [Apple hardware limits](https://support.apple.com/en-us/102501)

### Inferences

- Gate 1: pick a minimum macOS version and Intel policy separately from selecting App Store versus Developer ID. An App Store-first implementation should prototype any needed hardware path under sandbox and public-API constraints before promising it. A direct release is a candidate if private or privileged features prove central, with point-release and major-version compatibility risks.
- Gate 2: establish a MacBook built-in and a known DDC-capable USB-C/DisplayPort monitor. Add built-in HDMI on representative machines, a Thunderbolt/USB-C dock or KVM, a second identical display, an HDR/high-refresh panel, and a DisplayLink dock as separate cells. Add a native Apple external panel, AirPlay/Sidecar and Intel if those will be advertised. Record OS build, Mac chip, monitor model/firmware, route and operation result.
- Gate 3: repeat connect/reconnect, sleep/wake, clamshell, monitor input change, app crash/quit, duplicate monitor, permission denial, and an invalid or stale saved mode. Verify different monitors do not receive each other's commands and healthy controls survive a failed command. Prove timed revert and keyboard escape when changing modes. Block disconnecting or blacking out the last usable display and keep an obvious reset path on a working screen.
- Unit-test profile matching, mode ordering/selection, rollback and command timeout/retry logic against a simulated display backend. Only hardware tests can establish DDC, HDR fidelity, hotplug, and recovery behavior. Keep diagnostics local and redact serials before sharing.

### Gaps

- No physical tests or App Review submission were performed. The user's release channel, deployment floor, initial monitor inventory and Intel requirements are open product decisions.
