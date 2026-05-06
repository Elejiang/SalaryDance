# 薪动（SalaryDance）项目概览

`SPEC.md` 是项目 onepage。需要快速理解业务、架构、核心规则和文件分布时加载；详细实现规则见 `docs/`。

## 项目定位

- 中文名：薪动
- 英文名：SalaryDance
- Bundle ID：`com.salarydance.app`
- 形态：macOS 菜单栏 App，无传统主窗口。
- 核心入口：状态栏图标、状态栏实时金额、`NSPopover` 弹窗、设置窗口、全局快捷键。
- 核心价值：把工作日收入、工作进度、休息时间、摸鱼薪资和打工语录做成轻量、灵动、可配置的桌面反馈。

## 技术栈

| 类型 | 技术 |
|------|------|
| 语言 | Swift |
| UI | SwiftUI |
| macOS 桥接 | AppKit、Carbon HotKey |
| 配置存储 | `UserDefaults` + `JSONEncoder` / `JSONDecoder` |
| 网络 | `URLSession` 获取节假日数据 |
| 构建 | Xcode project / `xcodebuild` |
| 打包 | `scripts/package_dmg.sh` |

## 核心业务概念

| 概念 | 说明 |
|------|------|
| 基础日薪 | 用户输入的日薪/月薪/年薪先统一折算为基础日薪 |
| 补贴 | 支持多条按日/按月补贴；按日补贴进日薪，按月补贴可只进月薪或平摊进日薪 |
| 工作窗口 | `TimeRange` 表示工作开始和结束，支持跨夜 |
| 特殊工作日 | 有序规则覆盖命中当天的上下班时间，冲突时按优先级取第一条 |
| 休息时间 | 午休、晚饭独立开关，可选择是否计入计薪时长 |
| 工作进度 | 按完整工作窗口推进，休息是否计薪不影响时间百分比 |
| 摸鱼状态 | 用户在弹窗或快捷键手动切换，记录区间内有效计薪时间并折算为摸鱼薪资 |
| 计薪规则 | 每天、仅工作日、自定义工作日 |
| 节假日 | 通过 `ChineseHolidays` 自动获取并缓存 |
| 快捷键动作序列 | 一次快捷键按下执行序列中的下一项动作 |
| 导入导出 | 数据文件包含薪资、补贴、计薪规则、工作时间和摸鱼记录；配置文件包含展示、快捷键、颜色、刷新和应用偏好 |

## 模块关系

```text
SalaryDanceApp
  -> StatusBarController
      -> SalaryViewModel
      -> SalaryConfigManager
      -> OffTaskTracker
      -> PopoverView / SettingsWindow
      -> GlobalShortcutMonitor

SalaryConfigManager
  -> SalaryConfig
  -> UserDefaults

SalaryViewModel
  -> SalaryConfig
  -> ChineseHolidays
  -> OffTaskTracker

SettingsView
  -> SalaryConfigManager
  -> ChineseHolidays
  -> GlobalShortcutMonitor
  -> OffTaskTracker
```

## 关键文件

| 文件 | 重点 |
|------|------|
| `SalaryDance/Models/SalaryConfig.swift` | 配置字段、默认值、薪资换算、工作日判断、跨夜时间 |
| `SalaryDance/Models/SalaryWorkTimeline.swift` | 展开真实工作窗口、有效计薪区间 |
| `SalaryDance/Models/OffTaskTracker.swift` | 摸鱼区间持久化、当日和历史摸鱼薪资统计 |
| `SalaryDance/ViewModels/SalaryViewModel.swift` | 定时刷新、今日收入、工作状态、进度 |
| `SalaryDance/Views/FloatingPanelView.swift` | 状态栏、弹窗定位、设置窗口 |
| `SalaryDance/Views/SettingsView.swift` | 设置分栏、输入校验入口、展示配置 |
| `SalaryDance/Views/SalaryDisplayView.swift` | 弹窗薪资和时间轴展示 |
| `SalaryDance/Helpers/ChineseHolidays.swift` | 节假日/调休日缓存和加载 |
| `SalaryDance/Helpers/GlobalShortcutMonitor.swift` | Carbon 全局快捷键注册 |

## 默认配置摘要

默认值集中在 `SalaryConfig`：

- 薪资类型：月薪，金额 0。
- 补贴：默认空列表；新增补贴默认开启，名称为“补贴名”，按月补贴平摊默认固定 21.75 天。
- 工作时间：10:00 - 21:00。
- 特殊工作日规则：默认空列表。
- 午休：开启，12:00 - 14:00。
- 晚饭：开启，18:00 - 19:00。
- 计薪规则：仅工作日。
- 休息时间计薪：默认不计薪。
- 快捷键：Option + Command + Z。
- 摸鱼切换快捷键：Option + Command + X。
- 快捷键默认动作：打开状态栏实时显示、关闭状态栏实时显示。
- 弹窗默认脱敏：开启。
- 弹窗默认展示：当前收入、今日剩余、工作状态、秒薪、分薪、时薪、进度、打工语录、摸鱼状态。
- 弹窗摸鱼薪资/时长指标：默认关闭。
- 状态栏实时金额：默认开启。
- 状态栏摸鱼状态图标：默认开启，且默认仅在摸鱼中显示。
- 金额小数位：默认 2 位，范围 0-3。
- 工作进度小数位：默认 0 位，范围 0-3。
- 刷新间隔：默认 1 秒，范围 0.5-3600 秒。

## 计算规则摘要

- 输入日薪：基础日薪 = 输入值。
- 输入月薪：基础日薪 = 月薪 / 月薪折算天数。
- 输入年薪：基础日薪 = 年薪 / 250。
- 展示日薪 = 基础日薪 + 按日补贴 + 平摊到每天的按月补贴。
- 展示月薪 = 基础日薪 × 月薪折算天数 + 按日补贴 × 月薪折算天数 + 按月补贴原值。
- 展示年薪 =（基础日薪 + 按日补贴）× 250 + 按月补贴原值 × 12。
- 秒薪/分薪/时薪 = 展示日薪 / 当天有效计薪时长。
- 摸鱼薪资 = 摸鱼区间与当天有效计薪区间的重叠秒数 × 当天秒薪；休息时间不计薪时，摸鱼统计同样扣除休息段。
- 摸鱼状态只能在有效计薪区间开启；休息时间不计薪时，跨入午休或晚饭会自动结束本次记录。
- 摸鱼数据概览展示本日、本周、当前计薪周期；本周和当前计薪周期写明起止日期，当前计薪周期跟随 `SalaryCycleMode`，自然月展示为本月，固定周期展示为本周期。
- 弹窗摸鱼状态可选展示本日、本周、本月/本周期、历史的摸鱼薪资和摸鱼时长。
- 摸鱼历史记录按年-月-日折叠查看，单次记录支持删除；已结束记录可回溯编辑开始和结束时间，进行中记录可编辑开始时间，精确到秒。
- 已关闭补贴不参与上述任何计算。
- 特殊工作日只覆盖命中当天上下班时间，不改变计薪日、休息、补贴、月薪或年薪折算。

计薪周期支持：

- 自然月。
- 固定周期，每月指定起始日到次月前一日，起始日支持 1-31，短月按当月最后一天兜底。

月薪折算天数支持：

- 固定天数，默认 21.75，范围 1-31。
- 周期内工作天数，按当前计薪周期和“日历”计薪规则动态统计。

按月补贴平摊方式支持：

- 周期内总天数。
- 固定天数，默认 21.75，范围 1-31。
- 周期内工作日天数。

详细计算规则见 `docs/config-and-calculation.md`。

## 刷新机制摘要

`SalaryViewModel` 使用 `Timer`：

- 弹窗打开或状态栏实时金额开启时，使用用户配置间隔。
- 无实时展示且开启空闲低频时，使用 `max(60, resolvedRefreshIntervalSeconds)`。
- Timer tolerance 为 `min(5, max(0.2, interval * 0.25))`。
- 配置变更、快捷键切换、弹窗打开前会触发即时刷新。

## UI 摘要

- 主要界面包括状态栏、弹窗和设置窗口。
- 弹窗宽度固定 280。
- 状态栏实时金额使用 SwiftUI `NSHostingView` 嵌入 `NSStatusBarButton`。

详细 UI 和平台规则见 `docs/ui-and-appkit.md`。

## 构建与运行

```sh
xcodebuild -project SalaryDance.xcodeproj -scheme SalaryDance -configuration Debug -derivedDataPath /tmp/SalaryDanceDerivedData build
scripts/dev_run.sh
scripts/package_dmg.sh
```

详细开发流程见 `docs/development-guide.md`。
