# Changelog

Each `## <version>` section becomes that version's GitHub release notes
(`scripts/release.sh --upload`), and Netty shows its top-level bullets in the
update notification and in Settings › General. Keep each bullet one short line
about what a user gets. Write the next version's bullets under `## Unreleased`,
then rename the heading to the version before tagging.

## 1.1.0

- Update notices: Netty tells you when a new version is out, with what it brings
- Choose how often to check for updates, or check by hand, in Settings › General
- Install and upgrade with Homebrew: `brew install --cask alvaldes/tap/netty`

## 1.0.0

- Online, degraded or offline at a glance in the menu bar
- Latency, jitter and packet loss, checked every 10 seconds
- Speed tests with Apple's networkQuality, on demand or on a schedule
- Notifications when the connection drops and when it comes back
- Wi-Fi name, VPN, and local and public IP in the popover
