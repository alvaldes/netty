#if DEBUG
import AppKit
import NettyKit
import SwiftUI

/// Debug only: renders every Settings area, light and dark, to PNG files in an
/// offscreen window that is never shown, so the design can be reviewed
/// without opening the app. Run with `NETTY_RENDER_SETTINGS=<directory>`.
enum SettingsSnapshot {
    static func renderIfRequested() {
        guard let directory = ProcessInfo.processInfo.environment["NETTY_RENDER_SETTINGS"] else { return }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // Throwaway defaults: rendering must not touch the user's settings.
        let defaults = UserDefaults(suiteName: "com.alvaldes.netty.snapshot")!
        defaults.removePersistentDomain(forName: "com.alvaldes.netty.snapshot")
        let settings = NettySettings(defaults: defaults)
        for area in SettingsArea.allCases {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let view = SettingsView(settings: settings, launchAtLogin: LaunchAtLogin(),
                                        location: LocationPermission(), notifications: NotificationPermission(),
                                        previewModel: { PopoverSnapshot.samples[0].1 }, area: area)
                render(view, appearance: appearance, to: output.appending(path: "\(area.rawValue)-\(name).png"))
            }
        }
        settings.iconStyle.mode = .monochrome
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = SettingsView(settings: settings, launchAtLogin: LaunchAtLogin(),
                                    location: LocationPermission(), notifications: NotificationPermission(),
                                    previewModel: { PopoverSnapshot.samples[0].1 }, area: .icon)
            render(view, appearance: appearance, to: output.appending(path: "icon-monochrome-\(name).png"))
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let grid = GlyphGrid(current: .symbol("circle.dashed"), select: { _ in })
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
            render(grid, appearance: appearance, size: CGSize(width: 400, height: 180),
                   to: output.appending(path: "glyph-grid-\(name).png"))
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = OnboardingView(settings: settings, location: LocationPermission(),
                                      notifications: NotificationPermission(), requestNotifications: {})
                .background(Color(nsColor: .windowBackgroundColor))
            render(view, appearance: appearance, size: CGSize(width: 440, height: 560),
                   to: output.appending(path: "onboarding-\(name).png"))
        }
        exit(0)
    }

    private static func render(_ view: some View, appearance: NSAppearance.Name,
                               size: CGSize = CGSize(width: 880, height: 568), to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI settle its first layout pass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
