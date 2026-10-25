# CGBarStat

[中文](README.md)

A macOS menu bar app. Three status items show Cursor Models (CM), Other Models (OM), and Grok Bot (GB) from left to right. The top line of each item is the abbreviation, and the bottom line is the usage percentage. Percentages whose absolute value is at least 10 keep one decimal place; smaller values keep two.

## Download

The current version is [0.2.0](https://github.com/Yeyue56/cgbarstat/releases/tag/v0.2.0), for Apple silicon Macs running macOS 14 or later.

[Download CGBarStat-0.2.0-arm64.zip](https://github.com/Yeyue56/cgbarstat/releases/download/v0.2.0/CGBarStat-0.2.0-arm64.zip)

Other versions are listed on [Releases](https://github.com/Yeyue56/cgbarstat/releases).

Unzip the download to get `CGBarStat.app`. The current build is not notarized by Apple. The first time you open it, Control-click the app in Finder and choose Open. On macOS 26 or later, allow CGBarStat under System Settings → Menu Bar. The app does not appear in the Dock. Cursor must be installed and signed in on the Mac before use.

## Interface

The menu bar shows CM, OM, and GB from left to right. These three items in the figure are CGBarStat.

![CM, OM, and GB in the menu bar](docs/screenshots/menu-bar.png)

Hovering CM opens Cursor Models. The first row is the quota percentage and tokens for the current period. The second row is today's share of the period and today's tokens. Each following row is one model's bar, share, and tokens. Below the model list is the time until the plan period ends. At one day or more, that line shows days and hours. Below one day, it shows hours and minutes, followed by “后过期”. When the period has ended, the line is “套餐已过期”. The line is omitted when the response has no cycle end.

![Cursor Models panel](docs/screenshots/cursor-models.png)

Hovering OM opens Other Models. The layout matches CM. A model is classified as CM when its name, compared case-insensitively, contains `composer`, `grok`, or `cursor`, equals `auto`, or starts with `auto-`. Every other model is OM. In the figure, `github_bugbot` and `default` therefore appear under OM.

![Other Models panel](docs/screenshots/other-models.png)

Hovering GB opens Grok Bot. The panel shows only the percentage and the time until the next reset. At one day or more, it shows days and hours, followed by “后重置”.

![Grok Bot panel](docs/screenshots/grok-bot.png)

A model name that does not fit is truncated at the end. Hovering a truncated name shows the full name. A model row keeps its share and token count in separate columns. The share, including `100.0%`, stays on one line.

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

It reads `cursorAuth/accessToken`, `cursorAuth/refreshToken`, and the plan user id `cursorAuth/stripeMembershipAuthId` from `ItemTable`. Starting with Cursor 3.27, the access token and refresh token are stored with the `cursor-safe-storage:v1:` prefix. The app decrypts them in memory with the login-keychain item `Cursor Safe Storage` / `Cursor Key`. The password macOS asks for is the login keychain password: this Mac’s login password. If that login password was changed later, the keychain may still use the previous one. The password stays in memory for the current launch, so the prompt appears once per launch. Choosing Always Allow skips the question on later launches. Decrypted values remain in memory. The database, snapshot, logs, and repository do not store that plaintext. When the server issues a replacement token, the new value is written back to the original two keys.

When `api2.cursor.sh` rejects that access token, the app sends the plan user id and access token as a `WorkosCursorSessionToken` cookie to `https://cursor.com/api/dashboard/get-current-period-usage`. If the dashboard also rejects the session, the app exchanges the refresh token at `https://api2.cursor.sh/oauth/token` and writes the new tokens back to those same keys. Usage requests go only to `api2.cursor.sh`, `cursor.com`, and `www.cursor.com`. Automatic redirects are refused; an HTTPS redirect is retried once only when the new host is one of those three.

Usage comes from these `api2.cursor.sh` calls:

- `DashboardService/GetCurrentPeriodUsage`: `autoPercentUsed`, `apiPercentUsed`, and `billingCycleEnd`
- `DashboardService/GetPlanInfo`: `planInfo.billingCycleEnd` when the period-usage call is rejected
- `DashboardService/GetAggregatedUsageEvents`: model tokens for the current period and for today
- `DashboardService/GetSandUsageStatus`: Grok Bot `usagePercent` and `nextResetTimestampUtc`

When `api2.cursor.sh` rejects the access token, the same period usage is read from `cursor.com` at `api/dashboard/get-current-period-usage`. The fields match the period-usage call above.

These endpoints have no public compatibility guarantee. When the reset timestamp is absent, the interface shows “重置时间未知” and does not infer a 7-day period from the cycle start.

## Menu bar and panels

Status items are created in the order GB, OM, CM, so the visual order from left to right is CM, OM, GB. The layout is shown in Interface above. Below one day, the reset time is hours and minutes. At one day or more, it is days and hours. When the reset timestamp is absent, the text is “重置时间未知”. The CM and OM panels share one countdown for the plan period. When that period has ended, the text is “套餐已过期”. With no local Cursor login, the panel says “未检测到本机 Cursor 登录”. When the saved login is encrypted and the keychain has not allowed decryption, the panel says 「本机 Cursor 登录已加密。请允许 CGBarStat 读取钥匙串项 “Cursor Safe Storage”，允许后会自动刷新。」. When both the saved access token and refresh token are rejected, the panel says “本机保存的登录仍被服务器拒绝。请完全退出 Cursor，再从账号菜单退出并重新登录。” and does not keep labeling the previous usage as “数据已过期”. When a login is present but this refresh did not return usage, the previous snapshot stays and is marked “数据已过期”. With no previous snapshot, the panel says “用量暂时无法更新”.

## Refresh

The app refreshes at launch, every 300 seconds, and when the system wakes. While the keychain has not allowed decryption, the interval stays at 300 seconds, so the system prompt is not repeated on the short timer. While the server rejects the saved login, the app retries every 15 seconds, so a new Cursor login is picked up without quitting this app. When a panel changes from hidden to visible, it refreshes again if the last success was more than 30 seconds ago.

## Community

[LINUX DO](https://linux.do)

## License

This repository uses the [MIT License](LICENSE). Keep the copyright notice and license text to use, modify, and redistribute the software, including in closed-source software. The software is provided as is, without warranty.
