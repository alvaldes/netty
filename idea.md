# Netty

A native, lightweight macOS menu bar app that tells you at a glance whether you are really on the internet, how good the connection is, and how fast it is.

- **License:** GPL-3.0 (free and open source).
- **Status:** design draft — nothing implemented yet.
- **Differentiators:** free, open source, carefully designed look. Same stack and distribution as [JUMP](https://github.com/alvaldes/jump).

---

## 1. References

| Reference | What we take from it |
|---|---|
| [Netbar](https://netbar.xyz/) | Product benchmark: menu bar indicator + popover. |
| [Netdot](https://netdot.app/) | Product benchmark: minimal dot indicator. |
| [Online Check](https://sindresorhus.com/online-check) | Benchmark for a "real internet" check, not just "connected to a network". |
| [iStat Menus](https://bjango.com/mac/istatmenus/) | Popover density and readability. |
| [Mac Stats](https://mac-stats.com/) | Popover layout. |
| JUMP (`~/Developer/jump`) | Project structure, tooling, release script, landing page, settings UI components. |

---

## 2. Definitions

These terms have one meaning everywhere in the app and in the code.

- **Online:** the Mac can reach the internet. A network path alone is not enough: Wi-Fi without internet or a captive portal (hotel, airport) counts as **offline**.
- **Latency:** round-trip time of a TCP connect to a well-known host (1.1.1.1:443, 8.8.8.8:443). Not ICMP ping.
- **Jitter:** mean absolute difference between consecutive latency samples in the window.
- **Loss:** share of failed probes in the window.
- **Speed:** connection **capacity** (download / upload Mbps) measured by a speed test. It is not the current traffic. A speed test uses data and takes about 10–20 s, so it cannot run continuously: Netty shows the **last measured** speed and when it was measured.

---

## 3. Scope

### MVP

1. Menu bar agent (`LSUIElement = true`), no Dock icon.
2. **Status icon** in the menu bar, configurable (see §4.6):
   - Green — online, good quality.
   - Yellow — online, degraded (high latency, jitter or loss).
   - Red — offline.
3. **Popover** on click:
   - Status ("Online" / "Degraded" / "Offline") and how long it has been in that status.
   - Latency (ms), jitter (ms), loss (%).
   - Last speed test: ↓ Mbps / ↑ Mbps, responsiveness, and time of measurement.
   - Network: Wi-Fi name (SSID) or interface type (Ethernet, iPhone hotspot), VPN indicator.
   - Opening the popover probes immediately, so there is no re-check button.
   - Actions: **Run speed test**, Settings, Quit.
4. **Notifications** when the connection goes offline and when it comes back online. Each can be turned off. Degraded (Yellow) does not notify.
5. **Settings:** quality rules (see §4.3), probe interval, speed test schedule, notifications, launch at login, menu bar icon (see §4.6).
6. **Location permission onboarding**, required by macOS to read the Wi-Fi name. If denied, Netty still works and shows "Wi-Fi" without the name.

### After MVP

- Per-network quality rules (e.g. stricter at home, looser on a hotspot).
- Latency sparkline in the popover (last few minutes, in memory only).
- Auto-updates (Sparkle 2).

### Out of scope

- **Mac App Store.** Distribution is Developer ID + notarization, GitHub Releases and a Homebrew cask, as JUMP. No sandbox required.
- **Disconnection history.** No persisted event log.
- Analytics or telemetry of any kind.

---

## 4. Technical design

### 4.1 Platform & tooling

Same choices as JUMP.

| Area | Choice |
|---|---|
| Language | Swift 6, strict concurrency |
| Minimum OS | macOS 26 |
| UI | SwiftUI (`MenuBarExtra` with `.window` style, `Settings`) |
| Project | XcodeGen (`project.yml`) + a local SPM package (`NettyKit`) for testable logic |
| Login item | `SMAppService.mainApp` |
| Settings | One `@Observable` model backed by `UserDefaults` |
| Notifications | `UserNotifications` |

### 4.2 Modules

```
Netty
├── App            entry point, MenuBarExtra, popover, settings, onboarding
└── NettyKit
    ├── Path         NWPathMonitor: interface type, path changes (instant signal)
    ├── Probe        reachability + latency probes (URLSession / Network.framework)
    ├── Quality      pure rules engine: samples → Green / Yellow / Red (fully unit tested)
    ├── SpeedTest    wraps /usr/bin/networkQuality -c, parses its JSON
    ├── NetworkInfo  SSID (CoreWLAN + CoreLocation), VPN detection
    └── Notify       status-change notifications with debounce
```

### 4.3 Status rules (adjustable)

**Reachability probe** every *probe interval* (default 10 s): HTTP GET `http://captive.apple.com/hotspot-detect.html`, success only if the body is `Success` (a captive portal returns something else). Fallback: `https://www.google.com/generate_204` expecting 204. Any success = reachable.

**Latency probe** with each reachability probe: TCP connect time to 1.1.1.1:443 and 8.8.8.8:443, keep the faster one.

Metrics use a sliding window of the last *N* samples (default 6, i.e. one minute).

| Status | Rule (defaults) |
|---|---|
| Red | `NWPath` is unsatisfied (immediate), **or** *3* consecutive failed reachability probes. |
| Yellow | Online, and median latency ≥ *150 ms* **or** jitter ≥ *50 ms* **or** loss ≥ *20 %*. |
| Green | Online and none of the Yellow conditions. |

Hysteresis to avoid a flickering LED:
- Red → online after *2* consecutive successful probes.
- Yellow → Green only after the window stays under the thresholds for *2* consecutive evaluations.
- A path change (Wi-Fi switch, VPN on/off) triggers an immediate probe.

Every value in *italics* is a setting, with "Reset to defaults".

### 4.4 Speed test

- Uses Apple's built-in `networkQuality -c` (JSON output: download/upload throughput, responsiveness in RPM). No third-party servers, no extra dependency.
- Runs: on **Run speed test**, and optionally on a schedule (Off — default, every 1 h, 6 h, 24 h). Never while Offline.
- Settings shows the cost: each test can use hundreds of MB. Option to skip scheduled tests on expensive / constrained paths (`NWPath.isExpensive`, `isConstrained`, e.g. iPhone hotspot).
- Result is kept in memory (and the last one in `UserDefaults` so the popover is not empty after relaunch).

### 4.5 Network info

- **SSID:** `CWWiFiClient` returns the name only with Location Services authorized. Ask once during onboarding, explain why, degrade gracefully.
- **Local IP:** the IPv4 address of the interface carrying the traffic, read with `getifaddrs`; nothing leaves the Mac.
- **Public IP:** `https://1.1.1.1/cdn-cgi/trace`, the host the latency probe already uses, so no new party; HTTPS to an IP literal, so no DNS lookup. Measured at 70–360 ms and 191 bytes. Looked up when the popover opens, on a new network or after 5 minutes; can be turned off.
- **VPN:** heuristic — an active `utun`/`ipsec`/`ppp` interface carrying the default route. Shown as "VPN on" without naming the provider.

### 4.6 Menu bar icon

Two modes, chosen in Settings:

| Mode | How the status shows |
|---|---|
| **Color** | One SF Symbol per status, tinted green / yellow / red. |
| **Monochrome** | A template image (adapts to light / dark menu bar), so color cannot carry the status: the symbol's **shape** does. |

- **Symbols (both modes):** `circle`, `circle.fill`, `circle.slash`, `circle.dotted`, `circle.dashed`, `circle.dashed.inset.fill`, `circle.circle`, `circle.and.line.horizontal`. Defaults: Online `circle.fill`, Degraded `circle.dashed`, Offline `circle.and.line.horizontal`. No text characters or emoji; ones saved by earlier versions show as the default.
- **Picker:** a grid of the symbols, drawn with a readable name (SwiftUI's `Menu` drops item images on macOS).
- **Custom icons:** the user imports one image per status (SVG, PDF or PNG). In Monochrome mode only the image's alpha is used.
- **Adjustable:** glyph per status, size (assumption: 10–18 pt), live preview in Settings showing the three states.
