# 薪动（SalaryDance）项目概览

职责：提供项目全貌、核心业务概念、模块关系和长期架构边界。

## 项目定位

- 中文名：薪动
- 英文名：SalaryDance
- Bundle ID：`com.salarydance.app`
- 形态：macOS 菜单栏 App，无传统主窗口。
- 核心入口：状态栏图标、状态栏实时金额、`NSPopover` 弹窗、设置窗口、全局快捷键。

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
| 提前下班 | 用户可在工作窗口内提前下班，记录剩余有效计薪时间并折算为提前下班赚到的金额，可撤回 |
| 晚下班 | 用户可在真实下班后选择晚下班时长，默认无额外收入，按当天秒薪折算晚下班亏损，可撤回 |
| 计薪规则 | 每天、仅工作日、自定义工作日 |
| 节假日 | 通过 `ChineseHolidays` 自动获取并缓存 |
| 快捷键动作序列 | 一次快捷键按下执行序列中的下一项动作 |
| 导入导出 | 数据文件包含薪资、补贴、计薪规则、工作时间、摸鱼、提前下班和晚下班记录，不含节假日缓存；配置文件包含展示、快捷键、颜色、刷新、应用偏好和设置侧边栏宽度 |

## 模块关系

```text
SalaryDanceApp
  -> StatusBarController
      -> SalaryViewModel
      -> SalaryConfigManager
      -> OffTaskTracker
      -> WorkSessionTracker
      -> PopoverView / SettingsWindow
      -> GlobalShortcutMonitor

SalaryConfigManager
  -> SalaryConfig
  -> UserDefaults

SalaryViewModel
  -> SalaryConfig
  -> ChineseHolidays
  -> OffTaskTracker
  -> WorkSessionTracker

SettingsView
  -> SalaryConfigManager
  -> ChineseHolidays
  -> GlobalShortcutMonitor
  -> OffTaskTracker
  -> WorkSessionTracker
```

## 关键文件

| 文件 | 重点 |
|------|------|
| `SalaryDance/Models/SalaryConfig.swift` | 配置字段、默认值、薪资换算、工作日判断、跨夜时间 |
| `SalaryDance/Models/SalaryWorkTimeline.swift` | 展开真实工作窗口、有效计薪区间 |
| `SalaryDance/Models/OffTaskTracker.swift` | 摸鱼区间、提前下班和晚下班记录持久化及当日/历史统计 |
| `SalaryDance/ViewModels/SalaryViewModel.swift` | 定时刷新、今日收入、工作状态、进度、提前下班和晚下班状态 |
| `SalaryDance/Views/FloatingPanelView.swift` | 状态栏、弹窗定位、设置窗口 |
| `SalaryDance/Views/SettingsView.swift` | 设置分栏、输入校验入口、展示配置 |
| `SalaryDance/Views/SalaryDisplayView.swift` | 弹窗薪资和时间轴展示 |
| `SalaryDance/Helpers/ChineseHolidays.swift` | 节假日/调休日缓存和加载 |
| `SalaryDance/Helpers/GlobalShortcutMonitor.swift` | Carbon 全局快捷键注册 |

## 核心边界

- `SalaryConfig` 是配置、薪资数据和展示偏好的统一持久化模型；导入导出时由 `SalaryDataSettings` 和 `SalaryPreferenceSettings` 拆分可迁移分区。
- `SalaryWorkTimeline` 是工作窗口和有效计薪区间的统一来源；实时收入、摸鱼统计和编辑校验都应复用它。
- `SalaryCycleMode` 决定计薪周期归属，`MonthlySalaryCalculationMode` 只决定月薪与日薪互算分母，两者不能互相替代。
- `OffTaskTracker` 持久化原始摸鱼区间，金额、时长和周期汇总按当前薪资配置实时重算。
- `WorkSessionTracker` 持久化提前下班和晚下班原始记录；提前下班金额表示剩余计薪时长赚到的薪资，晚下班金额表示默认无收入时按当天秒薪折算的亏损。
- 状态栏、弹窗、设置窗口和快捷键入口集中由 `StatusBarController` 串联，UI 展示开关由 `SalaryConfig` 驱动。

## 详细文档

| 需要修改 | 先读 |
|----------|------|
| 薪资、补贴、时间、计薪规则、刷新、导入导出 | `docs/config-and-calculation.md` |
| 状态栏、弹窗、设置页、快捷键、AppKit 桥接 | `docs/ui-and-appkit.md` |
| 构建、运行、打包、Git 忽略和文档维护 | `docs/development-guide.md` |
| 开发前检查、代码审查和高风险变更 | `docs/common-pitfalls.md` |
