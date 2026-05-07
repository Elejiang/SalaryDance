# UI、状态栏与 AppKit 细节

职责：维护状态栏、弹窗、设置页、快捷键和 SwiftUI/AppKit 桥接规则。

## 状态栏

核心文件：`SalaryDance/Views/FloatingPanelView.swift`。

| 状态 | 行为 |
|------|------|
| App 图标、实时金额和摸鱼图标都不展示 | 从 `NSStatusBar.system` 移除 `NSStatusItem`，菜单栏不留空位 |
| 仅 App 图标展示 | 使用系统符号按钮作为可点击入口 |
| 实时金额或摸鱼图标展示 | 使用 SwiftUI `NSHostingView` 自定义内容 |
| 金额动画 | 支持滚动、跳动、关闭 |
| 状态栏金额颜色 | 默认白色，可配置 |
| 摸鱼状态图标 | 可单独开关，默认仅摸鱼中显示；关闭“仅摸鱼中显示”后常驻并随当前摸鱼状态切换图标 |
| 隐藏后恢复 | 再次启动已运行的 App 会打开 App 图标入口；主全局快捷键仍可按动作序列重新展示实时金额 |

## 弹窗窗口

- 使用 `NSPopover`；优先依附真实状态栏按钮，按钮不可见时使用透明锚点窗口。
- 弹窗展示后让 popover window 成为 key window，避免 SwiftUI material 按非激活窗口发灰。
- 点击弹窗外关闭；弹窗内点击保持打开。

## 弹窗内容

核心文件：

- `PopoverView.swift`
- `SalaryDisplayView.swift`
- `BalancedSalaryMetricGrid.swift`
- `WorkQuoteState.swift`
- `OffTaskTracker.swift`

规则：

- 弹窗宽度固定 280。
- 当前收入、今日剩余、状态、进度、各薪资指标、摸鱼状态、打工语录均可单独开关。
- 弹窗今日摸鱼摘要有独立展示开关，默认开启；工作中、未开始、休息中和下班后都使用同一套当日摸鱼统计文案。
- 弹窗摸鱼状态内可单独开关本日、本周、本月/本周期、历史的摸鱼薪资和摸鱼时长；脱敏打开时摸鱼金额也需要脱敏，时长不脱敏。
- 真实弹窗和预览应优先共用同一 SwiftUI 组件；主薪资区复用 `SalaryDisplayView`，摸鱼状态区复用共享面板，避免按钮、脱敏小眼睛和指标网格出现两套实现。

## 设置页

核心文件：

- `SettingsView.swift`
- `SettingsSupportViews.swift`
- `PopoverPreviewView.swift`

规则：

- 设置页采用左侧分类 + 右侧配置面板。
- 展示页的弹窗内容按基础信息、薪资指标、摸鱼状态和其他分组，避免开关过多时变成单层列表。
- 展示页右侧弹窗预览保持在原右栏内，随配置项滚动固定在右栏顶部，并与真实弹窗复用展示组件，避免预览被裁切或和实际效果漂移。
- 薪资、时间、摸鱼、应用等页面只负责输入、预览和操作入口；业务字段划分和计算规则以 `docs/config-and-calculation.md` 为准。

## 快捷键

核心文件：

- `GlobalShortcutMonitor.swift`
- `ShortcutRecorderView.swift`
- `SalaryConfig.swift`

规则：

- 快捷键动作是序列，每按一次执行下一项。
- 可选动作和默认值由 `SalaryConfig` 维护。
- 摸鱼切换是独立快捷键，可单独启停和录制。
