# 候选窗与基础词库修复实施计划

**目标：** 完成 feat.md 的两项改动并生成搜猫五笔 1.3.3 安装包。

**实现：** 保留 Swift/AppKit/InputMethodKit 结构，提高 CandidatePanel 的窗口层级；统一来源文案，清理交付资源并同步版本。

1. 在 `Tests/PreferencesSmoke.swift` 创建与候选窗重叠的 `NSPanel`，层级设为 `NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)`，在候选窗显示后将浮窗前置。使用 `CGWindowListCopyWindowInfo` 验证候选窗仍排在浮窗前面，并验证焦点、隐藏和重显。先运行原生测试，确认旧实现失败。
2. 修改 `Sources/CandidatePanel.swift`，在 `panel.isFloatingPanel = true` 之后使用 `panel.level = .screenSaver`，避免被重置为普通浮窗层级 3。运行同一原生测试，确认遮挡回归通过。
3. 修改 `Sources/DictionaryStore.swift` 的来源为“基础词库”，简化 `Sources/Preferences.swift` 的关于页说明。移除 `Resources/wubi.tsv` 中六条相关品牌词条，更新 `Tests/CoreTests.swift` 的总数为 112008，构建时由 `scripts/generate-pinyin.swift` 重新生成拼音资源。同步 README 的当前统计。
4. `Resources/Info.plist` 版本设为 1.3.3、构建号 6；同步 `scripts/build.sh`、`Resources/Distribution.xml`、`Resources/Installer/ReadMe.html` 与 README 的当前版本和功能说明。
5. 执行 `bash scripts/test.sh > build/tests-1.3.3.log 2>&1`。GUI 与 Seatbelt 测试如受工具沙箱限制，则通过审批机制在沙箱外运行相同测试，不改变产品安全策略。
6. 执行 `bash scripts/build.sh > build/build-1.3.3.log 2>&1`；使用 `pkgutil --expand-full` 展开新包，核对通用架构、版本 1.3.3、严格代码签名、词库资源、安装路径与升级配置。
7. 更新 `SHA256SUMS.txt` 并写入 `docs/验收记录-1.3.3.md`，记录实际结果与验证边界。完成后交付新 pkg 路径。
