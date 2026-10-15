# CGBarStat

[中文](README.md)

A macOS menu bar app. Three status items show Cursor Models (CM), Other Models (OM), and Grok Bot (GB) from left to right. The top line of each item is the abbreviation, and the bottom line is the usage percentage. Percentages whose absolute value is at least 10 keep one decimal place; smaller values keep two.

## Download

The current version is [0.1.0](https://github.com/Yeyue56/cgbarstat/releases/tag/v0.1.0), for Apple silicon Macs running macOS 14 or later.

[Download CGBarStat-0.1.0-arm64.zip](https://github.com/Yeyue56/cgbarstat/releases/download/v0.1.0/CGBarStat-0.1.0-arm64.zip)

Other versions are listed on [Releases](https://github.com/Yeyue56/cgbarstat/releases).

Unzip the download to get `CGBarStat.app`. The current build is not notarized by Apple. The first time you open it, Control-click the app in Finder and choose Open. On macOS 26 or later, allow CGBarStat under System Settings → Menu Bar. The app does not appear in the Dock. Cursor must be installed and signed in on the Mac before use.

## Interface

The menu bar shows CM, OM, and GB from left to right. These three items in the figure are CGBarStat.

![CM, OM, and GB in the menu bar](docs/screenshots/menu-bar.png)

Hovering CM opens Cursor Models. The first row is the quota percentage and tokens for the current period. The second row is today's share of the period and today's tokens. Each following row is one model's bar, share, and tokens.

![Cursor Models panel](docs/screenshots/cursor-models.png)

Hovering OM opens Other Models. The layout matches CM. A model is classified as CM when its name, compared case-insensitively, contains `composer`, `grok`, or `cursor`, equals `auto`, or starts with `auto-`. Every other model is OM. In the figure, `github_bugbot` and `default` therefore appear under OM.

![Other Models panel](docs/screenshots/other-models.png)

Hovering GB opens Grok Bot. The panel shows only the percentage and the time until the next reset. At one day or more, it shows days and hours, followed by “后重置”.

![Grok Bot panel](docs/screenshots/grok-bot.png)

A model name that does not fit is truncated at the end. Hovering a truncated name shows the full name.

![Full model name on hover](docs/screenshots/model-name-tooltip.png)

## Requirements

- macOS 14 or later
- Apple silicon
- Cursor installed and signed in on this Mac

## Build and run

Building from source requires the Swift 6 toolchain.

```bash
swift test
scripts/package-app.sh
open CGBarStat.app
```

`scripts/package-app.sh` writes `CGBarStat.app` at the repository root. The executable is `CGBarStat.app/Contents/MacOS/CGBarStatApp`. The bundle is built for the architecture of the machine running the script. The repository does not store the app bundle or zip; packaged builds are published on [Releases](https://github.com/Yeyue56/cgbarstat/releases).

## Data source

The app opens this file read-only:

`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`

It reads the key `cursorAuth/accessToken` from `ItemTable`. The token stays in memory only. It is not written to the snapshot, logs, or the repository. Usage requests go only to `https://api2.cursor.sh`, and redirects are refused.

Usage comes from these `api2.cursor.sh` calls:

- `DashboardService/GetCurrentPeriodUsage`: `autoPercentUsed`, `apiPercentUsed`
- `DashboardService/GetAggregatedUsageEvents`: model tokens for the current period and for today
- `DashboardService/GetSandUsageStatus`: Grok Bot `usagePercent` and `nextResetTimestampUtc`

These endpoints have no public compatibility guarantee. When the reset timestamp is absent, the interface shows “重置时间未知” and does not infer a 7-day period from the cycle start.

## Menu bar and panels

Status items are created in the order GB, OM, CM, so the visual order from left to right is CM, OM, GB. The layout is shown in Interface above. Below one day, the reset time is hours and minutes. At one day or more, it is days and hours. When the reset timestamp is absent, the text is “重置时间未知”.

## Refresh

The app refreshes at launch, every 300 seconds, and when the system wakes. When a panel changes from hidden to visible, it refreshes again if the last success was more than 30 seconds ago.

## Community

[LINUX DO](https://linux.do)

## License

This repository uses the [MIT License](LICENSE). Keep the copyright notice and license text to use, modify, and redistribute the software, including in closed-source software. The software is provided as is, without warranty.
