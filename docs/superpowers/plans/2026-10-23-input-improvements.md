# 搜猫五笔 1.1.0 实施计划

**目标：** 实现 feat.md 五项改进并交付新的双架构 macOS 安装包。

**设计：** 沿用 Swift/AppKit/InputMethodKit；输入状态和按键策略集中管理，控制器负责系统事件及上屏。中文模式有编码时，单击 Shift 上屏原始编码并进入英文；无编码时只切换模式。Shift 组合键不触发切换。菜单栏状态项只在输入法激活时显示，Caps Lock 按英文处理。中文标点随模式变化，移除独立开关。候选窗仅显示横排候选及选词编号，无候选时隐藏。方括号及中文方括号、减号、等号在组字时翻页。

**数据：** 用户 JSON 增加可选的 orders 编码到词序映射；旧文件缺省为空。排序在文件锁内读取最新数据后调整，原子保存；删除不丢失排序，恢复后回到相应位置。新造词继续优先，导入的排序覆盖同码本地排序，删除记录仍优先。

**技术：** 本机 Swift 编译器、AppKit、InputMethodKit、pkgbuild/productbuild，不增加依赖。

- [x] 在 Tests/CoreTests.swift 增加旧词库兼容、排序导入导出、删除恢复、跨实例修改及错误输入检查，先确认新排序行为失败。
- [x] 在 Sources/DictionaryStore.swift 实现排序持久化和上下移动；在 Sources/Preferences.swift 增加上移/下移按钮，边界和删除行禁用。
- [x] 在 Sources/InputSession.swift 集中 Shift 模式、翻页键及标点策略，新增 Tests/InputTests.swift 覆盖输入和组合键行为；接入 Sources/InputController.swift。
- [x] 修改 Sources/CandidatePanel.swift 为单行候选，点击选词、屏幕边界约束保留；新增真实 AppKit 控件检查。
- [x] 更新偏好设置文案、README.md、安装器说明和版本号为 1.1.0。
- [x] 执行 scripts/test.sh、scripts/build.sh，检查双架构、代码签名、安装包内容及 SHA256；记录验证范围。

实机安装、输入源注册和不同宿主应用中的输入另行说明实际验证范围，不把控件测试等同于系统输入法验收。
