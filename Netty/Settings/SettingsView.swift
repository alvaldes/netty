import NettyKit
import SwiftUI

/// The areas of the Settings window, in sidebar order.
enum SettingsArea: String, CaseIterable, Identifiable {
    case general, popover, icon, connection, speedTest, notifications, permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .popover: "Popover"
        case .icon: "Menu Bar Icon"
        case .connection: "Connection"
        case .speedTest: "Speed Test"
        case .notifications: "Notifications"
        case .permissions: "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .popover: "rectangle.stack"
        case .icon: "circle.dotted.circle"
        case .connection: "dot.radiowaves.left.and.right"
        case .speedTest: "speedometer"
        case .notifications: "bell.badge"
        case .permissions: "lock.shield"
        }
    }
}

/// The Settings window: a sidebar and one pane of cards per area.
struct SettingsView: View {
    let settings: NettySettings
    let launchAtLogin: LaunchAtLogin
    let location: LocationPermission
    let notifications: NotificationPermission
    let previewModel: () -> PopoverModel

    /// Every opening starts on General, which also holds About.
    @State var area: SettingsArea = .general
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $area)
            Divider()
            ScrollView {
                pane
                    .padding(.horizontal, 28)
                    .padding(.top, WindowChrome.titleBarHeight + 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        // The content runs under the transparent title bar.
        .ignoresSafeArea()
        .frame(width: 880, height: 540 + WindowChrome.titleBarHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowChrome(title: "Netty"))
        .task { await notifications.refresh() }
        .onDisappear { area = .general }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from System Settings.
            launchAtLogin.refresh()
            Task { await notifications.refresh() }
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch area {
        case .general: GeneralSettings(launchAtLogin: launchAtLogin)
        case .popover: PopoverSettings(settings: settings, previewModel: previewModel)
        case .icon: IconSettings(settings: settings)
        case .connection: ConnectionSettings(settings: settings)
        case .speedTest: SpeedTestSettings(settings: settings)
        case .notifications: NotificationSettings(settings: settings, permission: notifications)
        case .permissions: PermissionsSettings(location: location, notifications: notifications)
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsArea
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                NettyMark(size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Netty").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Version \(AppVersion.short)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 18)

            ForEach(SettingsArea.allCases) { area in
                Button {
                    selection = area
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: area.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(area.title)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(.rect)
                    .background {
                        if selection == area {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Brand.cardWash(scheme))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Brand.hairline(scheme)))
                                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 2, y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityAddTraits(selection == area ? .isSelected : [])
            }
            Spacer()
        }
        .padding(14)
        .padding(.top, WindowChrome.titleBarHeight)
        .frame(width: 200)
        .background(.ultraThinMaterial)
    }
}
