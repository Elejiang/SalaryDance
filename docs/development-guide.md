# 开发流程与仓库规范

职责：维护构建、运行、打包、仓库产物和文档维护流程。

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

提交前按 `AGENTS.md` 的“Git 提交规范”选择 type 和提交信息格式。

## 文档维护

- Spec 文档长期维护，代码长期契约变化必须同步更新。
- 收尾时检查配置字段、核心计算规则、刷新机制、打包流程、模块边界和开发流程。
- 一次性修复或局部实现细节不沉淀到知识库。
- 文档与代码不一致时，以代码为准，并同步修正文档。
