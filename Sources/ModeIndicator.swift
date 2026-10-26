import AppKit

private final class ModePanel: NSPanel {
 override var canBecomeKey: Bool { false }
 override var canBecomeMain: Bool { false }
}

/// Brief, non-interactive on-screen feedback; never creates a menu-bar item.
final class ModeIndicator {
 static let shared = ModeIndicator()
 private let panel: NSPanel
 private let label = NSTextField(labelWithString: "")
 private var dismiss: DispatchWorkItem?
 private weak var owner: AnyObject?
 init() {
  panel = ModePanel(contentRect: NSRect(x: 0, y: 0, width: 132, height: 64), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  panel.setAccessibilityIdentifier("soumao.modeToast")
  panel.level = .popUpMenu
  panel.isReleasedWhenClosed = false
  panel.ignoresMouseEvents = true
  panel.hidesOnDeactivate = false
  panel.isOpaque = false
  panel.backgroundColor = .clear
  panel.hasShadow = true
  panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
  let background = NSVisualEffectView(frame: panel.contentView!.bounds)
  background.material = .hudWindow
  background.state = .active
  background.wantsLayer = true
  background.layer?.cornerRadius = 14
  background.layer?.masksToBounds = true
  label.font = .systemFont(ofSize: 24, weight: .medium)
  label.alignment = .center
  label.translatesAutoresizingMaskIntoConstraints = false
  background.addSubview(label)
  NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: background.centerXAnchor), label.centerYAnchor.constraint(equalTo: background.centerYAnchor)])
  panel.contentView = background
 }
 func show(title: String, owner: AnyObject) {
  dismiss?.cancel()
  self.owner = owner
  label.stringValue = title
  let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
  let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
  panel.setFrameOrigin(NSPoint(x: bounds.midX - panel.frame.width / 2, y: bounds.minY + bounds.height * 0.22))
  panel.orderFrontRegardless()
  let task = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
  dismiss = task
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
 }
 func hide(owner: AnyObject) {
  guard self.owner === owner else { return }
  dismiss?.cancel(); dismiss = nil
  panel.orderOut(nil); self.owner = nil
 }
}
