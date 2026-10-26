import AppKit
import InputMethodKit
import Carbon

// Fail closed: no preferences, input server or dictionary is initialized unless
// the OS has applied the process-wide network denial policy.
guard soumao_deny_network() == 0 else { exit(78) }
if CommandLine.arguments.contains("--network-self-test") { exit(soumao_test_network_denial()) }

if CommandLine.arguments.contains("--register") {
 let bundleURL = Bundle.main.bundleURL
 let result = TISRegisterInputSource(bundleURL as CFURL)
 print("TISRegisterInputSource: \(result)")
 exit(result == noErr ? 0 : 1)
}

final class AppContext {
 static var store: DictionaryStore?
 static var pinyin: PinyinDictionary?
 static var preferences: PreferencesController?
 static func showPreferences() {
  guard let store = store else { return }
  if preferences == nil { preferences = PreferencesController(store: store) }
  preferences?.show()
 }
 static func showError(_ error: Error) {
  NSApplication.shared.activate(ignoringOtherApps: true)
  let alert = NSAlert()
  alert.messageText = "搜猫五笔"
  alert.informativeText = error.localizedDescription
  alert.alertStyle = .warning
  alert.runModal()
 }
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
 private var server: IMKServer?
 func applicationDidFinishLaunching(_ notification: Notification) {
  UserDefaults.standard.register(defaults: ["autoCommit": false])
  do {
   guard let base = Bundle.main.url(forResource: "wubi", withExtension: "tsv") else { throw DictionaryError(message: "缺少内置词库，请重新安装。") }
   let directory: URL
   if let custom = ProcessInfo.processInfo.environment["SOUMAO_USER_DIR"] {
    directory = URL(fileURLWithPath: custom, isDirectory: true)
   } else if let index = CommandLine.arguments.firstIndex(of: "--user-data-dir"), CommandLine.arguments.indices.contains(index + 1) {
    directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
   } else {
    directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SoumaoWubi", isDirectory: true)
   }
   AppContext.store = try DictionaryStore(baseURL: base, userURL: directory.appendingPathComponent("user-dictionary.json"))
   guard let pinyinURL = Bundle.main.url(forResource: "pinyin", withExtension: "tsv") else { throw DictionaryError(message: "缺少拼音词库，请重新安装。") }
   AppContext.pinyin = try PinyinDictionary(url: pinyinURL)
   // A direct preferences launch also serves input sessions when installed.
   server = IMKServer(name: "SoumaoWubi_Connection", bundleIdentifier: Bundle.main.bundleIdentifier!)
   guard server != nil else { throw DictionaryError(message: "无法启动输入服务；请确认没有另一个搜猫五笔实例运行。") }
   setupMenu()
   if CommandLine.arguments.contains("--preferences") || CommandLine.arguments.contains("--diagnose") { AppContext.showPreferences() }
   if CommandLine.arguments.contains("--diagnose") {
    let controllerReady = NSClassFromString("SoumaoInputController") != nil
    let windowReady = AppContext.preferences?.window?.isVisible == true
    let networkReady = soumao_test_network_denial() == 0
    print("INPUT_SERVICE_READY=\(server != nil) CONTROLLER_READY=\(controllerReady) PREFERENCES_VISIBLE=\(windowReady) DICTIONARY_PAIRS=\(AppContext.store?.baseCount ?? 0) NETWORK_DENIED=\(networkReady)")
    fflush(stdout)
    exit(controllerReady && windowReady && networkReady ? 0 : 1)
   }
  } catch { AppContext.showError(error); NSApplication.shared.terminate(nil) }
 }
 private func setupMenu() {
  let menu = NSMenu()
  let appItem = NSMenuItem()
  menu.addItem(appItem)
  let appMenu = NSMenu(title: "搜猫五笔")
  let prefs = NSMenuItem(title: "偏好设置…", action: #selector(openPreferences), keyEquivalent: ",")
  prefs.target = self; appMenu.addItem(prefs)
  let close = NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
  appMenu.addItem(close)
  appItem.submenu = appMenu
  let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
  let edit = NSMenu(title: "编辑")
  for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
   edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key))
  }
  editItem.submenu = edit; menu.addItem(editItem)
  NSApplication.shared.mainMenu = menu
 }
 @objc private func openPreferences() { AppContext.showPreferences() }
 func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
  AppContext.showPreferences(); return true
 }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = ApplicationDelegate()
app.delegate = delegate
app.run()
