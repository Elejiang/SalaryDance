# UI、状态栏与 AppKit 细节

本文档说明状态栏、弹窗、设置页、快捷键和 SwiftUI/AppKit 桥接规则；修改 UI 或 macOS 平台行为时加载。

## 状态栏

核心文件：`SalaryDance/Views/FloatingPanelView.swift`。

| 状态 | 行为 |
|------|------|
| 实时金额关闭 | 只显示系统符号图标 |
| 实时金额开启 | 使用 SwiftUI `NSHostingView` 自定义内容 |
| 金额动画 | 支持滚动、跳动、关闭 |
| 状态栏金额颜色 | 默认白色，可配置 |

## 弹窗定位

弹窗使用 `NSPopover`，依附状态栏入口展示，点击弹窗外关闭。

## 弹窗内容

核心文件：

- `PopoverView.swift`
- `SalaryDisplayView.swift`
- `BalancedSalaryMetricGrid.swift`
- `WorkQuoteState.swift`

规则：

- 弹窗宽度固定 280。
- 当前收入、今日剩余、状态、进度、各薪资指标、打工语录均可单独开关。
- 真实弹窗和预览共用同一布局语义。

## 设置页

核心文件：

- `SettingsView.swift`
- `SettingsSupportViews.swift`
- `PopoverPreviewView.swift`

规则：

- 设置页采用左侧分类 + 右侧配置面板。

## 快捷键

核心文件：

- `GlobalShortcutMonitor.swift`
- `ShortcutRecorderView.swift`
- `SalaryConfig.swift`

规则：

- 默认快捷键：Option + Command + Z。
- 快捷键动作是序列，每按一次执行下一项。
- 默认序列：打开状态栏实时显示、关闭状态栏实时显示。
- 可选动作：打开状态栏实时显示、关闭状态栏实时显示、脱敏打开窗口、不脱敏打开窗口、关闭窗口。
