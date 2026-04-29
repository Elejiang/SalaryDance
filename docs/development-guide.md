# 开发流程与仓库规范

本文档说明构建、运行、打包和文档维护规则；修改工程配置、脚本、提交历史或文档时加载。

## 构建

常用构建命令：

```sh
xcodebuild -project SalaryDance.xcodeproj -scheme SalaryDance -configuration Debug -derivedDataPath /tmp/SalaryDanceDerivedData build
```

注意：

- 构建目标是 macOS App。
- 新增 Swift 文件后，必须同步加入 `SalaryDance.xcodeproj/project.pbxproj`。

## 本地启动

本地启动入口统一使用脚本：

```sh
scripts/dev_run.sh
```

脚本行为：

1. 使用 `xcodebuild` 构建 Debug 包。
2. 关闭已运行的 `com.salarydance.app` 实例。
3. 打开 `.build/DerivedData/Build/Products/Debug/SalaryDance.app`。

## 打包 DMG

```sh
scripts/package_dmg.sh
```

打包脚本负责生成可分发 DMG。`dist/` 和 `build/` 产物不进入 Git。

## Git 忽略

必须忽略：

- `.DS_Store`
- `build/`
- `dist/`
- `DerivedData/`
- `.build/`
- `.swiftpm/`
- `xcuserdata/`
- `*.xcuserstate`

## Git 提交规范

提交规范只维护在 `AGENTS.md` 的“Git 提交规范”章节，避免两处表格不一致。提交前先按 `AGENTS.md` 选择合适的 type。

## 文档维护

- `AGENTS.md` 是精简规则和索引。
- `SPEC.md` 是项目 onepage。
- `docs/` 存放详细专题知识。
- 每次功能、重构、修复、配置、刷新、计算、打包流程变化后，都要更新对应文档。
- 文档与代码不一致时，以代码为准，并同步修正文档。
