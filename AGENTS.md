# 薪动（SalaryDance）协作规范

薪动是一个 macOS 菜单栏 App，用实时薪资、工作进度、休息时间、快捷键和弹窗展示，让用户直观看到“今天赚了多少”。项目以 SwiftUI + AppKit 混合实现，核心入口是状态栏、弹窗和设置窗口。

## 快速入口

- 构建：`xcodebuild -project SalaryDance.xcodeproj -scheme SalaryDance -configuration Debug -derivedDataPath /tmp/SalaryDanceDerivedData build`
- 本地启动：`scripts/dev_run.sh`
- 打包 DMG：`scripts/package_dmg.sh`
- Xcode 工程：`SalaryDance.xcodeproj`
- Bundle ID：`com.salarydance.app`

## 模块结构

| 路径 | 职责 |
|------|------|
| `SalaryDance/SalaryDanceApp.swift` | App 入口，启动状态栏和全局快捷键 |
| `SalaryDance/Models/SalaryConfig.swift` | 配置模型、薪资换算、时间段、快捷键动作 |
| `SalaryDance/ViewModels/SalaryViewModel.swift` | 今日收入、工作状态、进度、刷新定时器 |
| `SalaryDance/Helpers/` | 节假日、全局快捷键、开机启动 |
| `SalaryDance/Views/FloatingPanelView.swift` | 状态栏控制器、弹窗定位、设置窗口控制 |
| `SalaryDance/Views/SettingsView.swift` | 设置页主体 |
| `SalaryDance/Views/SalaryDisplayView.swift` | 弹窗薪资、进度、状态展示 |
| `scripts/` | 本地开发启动和 DMG 打包脚本 |

## 操作红线

- 配置模型以现行结构为准，不维护历史字段迁移；不兼容变更通过重置本地配置处理。
- 仓库只提交源码、脚本和文档，排除 `build/`、`dist/`、`.DS_Store`、`xcuserdata/`、DerivedData 等本地产物。
- 新增 Swift 文件必须同步加入 `SalaryDance.xcodeproj/project.pbxproj`。

## 代码风格

- 优先沿用现有 SwiftUI/AppKit 混合结构，不为了抽象而抽象。
- 注释覆盖关键配置、计算、状态流转、AppKit/SwiftUI 桥接和非直观 UI 布局；解释原因和边界，不逐行复述代码。
- 关键声明和关键逻辑块需要有解释原因和边界的注释。
- 设置项较多时优先分区、预览和输入校验，不堆叠长说明。
- UI 修改要保持真实弹窗、状态栏和设置预览的展示逻辑一致。

## Git 提交规范

提交信息格式使用 `<type>: <subject>`，例如 `feat: v1.0`。

| type | 含义 | 使用场景 |
|------|------|----------|
| `feat` | 新功能 | 新增某个功能或特性 |
| `fix` | 修复 bug | 修复了某个问题或 Bug |
| `docs` | 文档更新 | 仅修改了文档，如 README、AGENTS、SPEC |
| `style` | 代码风格调整 | 不影响代码含义的格式调整，非 CSS 样式 |
| `refactor` | 代码重构 | 既不是修复 bug 也不是添加功能的结构优化 |
| `perf` | 性能优化 | 提高性能的代码更改 |
| `test` | 测试相关 | 添加或修改测试用例 |
| `chore` | 工具/依赖维护 | 辅助工具、脚本、依赖维护 |
| `build` | 构建系统 | 影响构建系统或外部依赖的更改 |
| `ci` | 持续集成 | CI 配置和脚本更改 |
| `revert` | 回滚提交 | 撤销之前的提交 |

## 知识库（渐进式加载）

需要更详细信息时，按需加载以下文档：

| 层级 | 文件 | 加载时机 | 内容 |
|------|------|----------|------|
| L1 | `SPEC.md` | 需要项目全貌、业务概念和模块关系时 | 项目 onepage |
| L2 | `docs/development-guide.md` | 构建、运行、打包、文档维护 | 开发流程 |
| L2 | `docs/config-and-calculation.md` | 修改薪资、时间、刷新、节假日逻辑 | 配置与计算 |
| L2 | `docs/ui-and-appkit.md` | 修改状态栏、弹窗、设置页、AppKit 桥接 | UI 与平台细节 |
| L2 | `docs/common-pitfalls.md` | 开发前检查、代码审查、维护红线 | 风险点与检查清单 |

## 知识库维护

本项目的 Spec 知识体系是持续维护的活文档：

- 代码即真相：文档与代码不一致时，以代码为准，并主动更新文档。
- 长期契约变化后更新对应文档，包括配置字段、核心计算规则、刷新机制、打包流程、模块边界和开发流程。
- 一次性功能迭代、局部修复、实现细节微调不沉淀到 `SPEC.md`、L2 文档或项目规范文档，除非它改变长期约定或会影响后续开发判断。
- 新增模块或重大重构后，评估是否需要更新 `SPEC.md` 和 L2 文档。
- 知识不重复：根文档只放规则和索引，细节放入对应 L2 文档。
