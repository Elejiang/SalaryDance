# 风险点与检查清单

职责：维护高风险区域、审查清单和新增配置/Swift 文件检查项。

## 高风险区域

| 区域 | 风险 | 检查点 |
|------|------|--------|
| `SalaryViewModel` | 跨夜工作窗口 | 晚班、下班后、昨日窗口仍在进行中 |
| `SalaryConfig` | 配置默认值和计算 | 现行配置结构、默认值、normalize |
| `OffTaskTracker` | 摸鱼区间归属和自动结算 | 跨夜、休息不计薪、下班后未手动结束 |
| `WorkSessionTracker` | 提前下班和晚下班归属 | 提前下班不扣今日收入、晚下班默认无收入、跨夜归属和撤回 |

## 审查清单

- 仓库卫生：构建产物、DMG、本地 Xcode 用户状态不进入 Git。
- 薪资计算：对照 `docs/config-and-calculation.md` 的薪资、补贴、周期和休息规则，确认没有绕过 `SalaryConfig` 的规范化字段。
- 时间边界：涉及工作窗口、计薪区间、摸鱼、提前下班或晚下班统计时，复用 `SalaryWorkTimeline`，不要在 UI 或设置页重新拼时间区间。
- 摸鱼记录：编辑和删除只能操作原始 `OffTaskSession`，金额、时长和周期汇总都由 `OffTaskTracker` 重新计算。
- 提前下班/晚下班记录：撤回只能删除原始 `ClockOutSession` 或 `OvertimeSession`；提前下班金额是赚到的薪资，晚下班金额是默认无收入时的亏损。
- 导入导出：数据分区和配置分区保持字段零交集；新增可迁移字段时同步更新 `SalaryDataSettings` 或 `SalaryPreferenceSettings`。
- UI 一致性：状态栏、真实弹窗和设置预览展示同一类内容时，优先复用共享组件或共享展示模型。
- 文档一致性：长期规则变化同步更新 Spec 文档，避免代码和 AI 开发上下文漂移。

## 新增配置字段清单

新增 `SalaryConfig` 字段时检查：

1. 字段有默认值。
2. `normalize()` 修正非法值。
3. 如果影响展示，设置页、真实弹窗和预览同步更新。
4. 如果影响计算，`SPEC.md` 或 `config-and-calculation.md` 同步更新。
5. 字段加入 `CodingKeys` 和自定义 `init(from:)`，用 `decodeLossy` / `decodeIfPresent` 兼容旧配置。
6. 新增或改名枚举展示文案时，不修改持久化 raw value；历史文案别名放到枚举自定义解码里。

## 新增 Swift 文件清单

新增 Swift 文件时检查：

1. 文件放在合适目录。
2. 加入 `SalaryDance.xcodeproj/project.pbxproj` 的 FileReference、Group、Sources。
3. 构建通过。
4. 文档索引需要时同步更新。
