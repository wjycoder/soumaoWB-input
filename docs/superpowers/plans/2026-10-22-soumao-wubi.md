# 搜猫五笔实施计划

目标：交付完全离线、独立开发、可由系统设置添加的原生五笔输入法安装包。
架构：Swift/AppKit/InputMethodKit；只读 TSV 基础词库 + 本地 JSON 用户叠加；进程启动先施加 Seatbelt 网络拒绝。
执行：在本会话按 executing-plans 执行。独立研究交由 REA 技能要求的并行研究任务；实现按模块验证。

- [x] `Tests/CoreTests.swift`：先定义真实词库、删词作用域、造词、恢复、重载、导入拒绝非法输入、原子保存、分页/选词/取消的断言，运行确认缺少实现。
- [x] `Sources/DictionaryStore.swift`：`DictionaryStore(baseURL:userURL:)`、`candidates(for:)`、`rows(for:)`、`add(code:word:)`、`remove(code:word:)`、`restore(code:word:)`、`export(to:)`、`importChanges(from:)`。用 Codable 持久化，写入成功后才发布内存状态；文件不存在为空，文件损坏抛错且不覆盖。
- [x] `Sources/Composition.swift`：输入状态与 GUI 分离，处理字母、空格、数字、分页、删除、取消、四码候选提交。测试使用实际候选集合，确认空格无候选不吞原始编码。
- [x] `Sources/NetworkGuard.c` 与桥接头：程序启动先 `(version 1)(allow default)(deny network*)`；失败立即停止；`--network-self-test` 验证 IPv4/IPv6 TCP、UDP 被 EPERM 拒绝。
- [x] `Sources/Preferences.swift`：原生常规/高级设置/关于；高级设置按码列出词，单独删除/恢复/造词、用户数据导入导出；错误弹窗且保留数据。用同一 DictionaryStore。
- [x] `Sources/InputController.swift`、`CandidatePanel.swift`、`main.swift`：IMKInputController 桥接到组合状态；候选窗跟随光标且不夺焦点；菜单打开偏好设置；保留快捷键透传。`--preferences` 可独立启动管理窗。
- [x] `Resources/Info.plist` 与原创建图标：独立 bundle ID、连接名、控制器名、zh-Hans 输入模式；不含原 app 代码/资源。
- [x] `scripts/build.sh`：Swift 分别构建 arm64/x86_64 macOS 14，lipo 合并，ad-hoc 签名；pkgbuild 打包到 `/Library/Input Methods/SoumaoWubi.app`；最终包输出当前目录。
- [x] 验证：核心测试、网络拒绝测试、原生 UI 启动、签名检查、安装包展开与 bundle 检查。实际系统安装若受权限限制，明确列为待用户安装验收；不伪造通过结果。
- [x] 交付 README、来源报告、测试记录、源码与 .pkg 文件；说明候选基础排序不声称与搜狗个性化排序完全一致。

执行完成；系统级安装和跨应用验收未在受限环境执行，详见 docs/验收记录.md。
