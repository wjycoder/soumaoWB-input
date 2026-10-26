# macOS 系统输入法集成：已核实事实

日期：2026-10-22。研究环境 macOS 27.0.1 / arm64，Apple Swift 6.4，Command Line Tools 已安装。

## 搜狗样本

- 路径：`/Library/Input Methods/SogouWBInput.app`
- 版本：1.4.0.148。
- 可执行文件 SHA-256：`680320ddc970225d228639138f257e73818f095f5c91260c246e412d9d751815`。
- `wubi.dic` SHA-256：`84076d8204d2bfbe8024de5337b746b8d140bb280b3973dedec40bd884000f11`，903884 字节。
- Info.plist 证据：`ev_6f68006b7e2549c7d4704cab1fb8a153ce1eb12340e808b3cbe11e4651e50d16`，完整记录保存在同目录 sogou-plist-evidence.json。
- Mach-O 摘要证据：`ev_a953d286b7ad4b3ee19b15498112bbb520c101e0c117f3f8a067c43678b6602f`，原记录 `ev_d3cae4a7c049e736d4eddf84ebd57032d835648ec58b5494a5361fd451bf07c5`。arm64 与 x86_64 两个 slice；符号集合并不保证完整。
- Info.plist 观察到 InputMethodConnectionName、InputMethodServerControllerClass、ComponentInputModeDict、smSimpChinese、LSBackgroundOnly。
- 未运行或修改搜狗应用；以上是静态观察。

## Apple SDK 的直接依据

`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/TextInputSources.h`

- 1199–1254 行：TISRegisterInputSource 注册输入源，输入法必须位于 `/Library/Input Methods/` 或 `~/Library/Input Methods/`。函数报告注册状态，注册后可通过 TISCreateInputSourceList 查询。
- 1258 行起：TISInputSourceID 和 TISIntendedLanguage 可用于输入法和输入模式；语言使用 BCP 47。
- 注册、启用和选择输入源是不同操作；安装不应自动替用户切换当前输入法。

`InputMethodKit.framework/Headers/IMKServer.h` 与 `IMKInputController.h`

- 一个应用应创建一个 IMKServer；它为每个输入会话创建控制器。
- 可以使用 handleEvent:client: 接收 NSEvent，或 inputText:key:modifiers:client: 接收解析后的按键。
- 返回 NO 将未处理按键交回客户端；控制器需正确处理 commitComposition 和 activate/deactivate。
- 默认只处理 keyDown 时，系统负责在点击组合区外时请求提交。

## 构建边界

- `security find-identity -v -p codesigning` 返回 0 个有效身份。可做本地 ad-hoc 代码签名，不能声称有 Developer ID 签名/Apple 公证。
- 当前允许写入目录不含系统输入法目录或用户输入法目录。可以在工作目录构建完整安装包并做展开验证；系统安装和真实输入源验收不能在未取得宿主允许的情况下假定已完成。
- `file wubi.dic` 的 xBase 猜测与实际头部/内容不匹配，不能作为格式结论；实际格式须由边界与全量解析验证。
