# CGBarStat

macOS 菜单栏应用。三个状态项从左到右显示 Cursor Models（CM）、Other Models（OM）和 Grok Bot（GB）。每一项上行是简拼，下行是用量百分比。百分比绝对值达到 10 时保留 1 位小数，不足 10 时保留 2 位小数。

## 环境

- macOS 14 或更新版本
- 本机已安装并登录 Cursor
- Swift 6 工具链

## 构建与运行

```bash
swift test
scripts/package-app.sh
open CGBarStat.app
```

macOS 26 及更新版本要在「系统设置 → 菜单栏」中允许 CGBarStat 显示状态项。打包会把 `Support/AppIcon.icns` 放进应用，Finder 里使用这张图标。应用仍然不出现在 Dock。

## 数据来源

应用用只读方式打开：

`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`

从 `ItemTable` 读取键 `cursorAuth/accessToken`。令牌只留在内存中。

用量来自 `api2.cursor.sh` 上的：

- `DashboardService/GetCurrentPeriodUsage`：`autoPercentUsed`、`apiPercentUsed`
- `DashboardService/GetAggregatedUsageEvents`：本期与今日的模型 Tokens
- `DashboardService/GetSandUsageStatus`：Grok Bot 的 `usagePercent` 与 `nextResetTimestampUtc`

这些接口没有公开兼容保证。没有重置时间戳时，界面显示「重置时间未知」，不用周期起点推算 7 天。

## 状态栏与悬浮窗

状态项按 GB、OM、CM 的顺序创建，使视觉顺序从左到右为 CM、OM、GB。

CM 与 OM 的悬浮窗第一行是额度百分比和本期 Tokens，第二行是今日 Tokens 占本期 Tokens 的比例和今日 Tokens，之后每行是一个模型的进度条、占比和 Tokens。模型名超出宽度时尾部省略，悬停被省略的名称会显示完整名称。GB 的悬浮窗只有百分比和距离下次重置的时间。不足一天时是小时和分钟，达到一天时是天和小时，时间后面加上「后重置」。没有重置时间戳时仍显示「重置时间未知」。

## 刷新

应用启动、每 300 秒、系统唤醒时刷新。面板从隐藏变为显示时，若距离上次成功超过 30 秒，再刷新一次。
