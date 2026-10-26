import AppKit

private final class NonactivatingPanel: NSPanel {
 override var canBecomeKey: Bool { false }
 override var canBecomeMain: Bool { false }
}
final class CandidatePanel {
 private let panel: NSPanel
 private let stack = NSStackView()
 private var selection: ((Int) -> Void)?
 init() {
  panel = NonactivatingPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  panel.setAccessibilityIdentifier("soumao.candidates")
  panel.level = .popUpMenu
  panel.isFloatingPanel = true
  panel.hidesOnDeactivate = false
  panel.isReleasedWhenClosed = false
  panel.hasShadow = true
  panel.backgroundColor = .windowBackgroundColor
  panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
  stack.orientation = .horizontal
  stack.alignment = .centerY
  stack.spacing = 18
  stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
  panel.contentView = stack
 }
 func hide() { panel.orderOut(nil); selection = nil }
 func show(candidates: [InputCandidate], anchor: NSRect, selection: @escaping (Int) -> Void) {
  guard !candidates.isEmpty else { hide(); return }
  self.selection = selection
  for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
  let screen = NSScreen.screens.first { NSIntersectsRect($0.frame, anchor) } ?? NSScreen.main
  let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
  var buttons: [NSButton] = []
  for (index, candidate) in candidates.prefix(5).enumerated() {
   let word = candidate.displayText
   let button = NSButton(title: "\(index + 1) \(word)", target: self, action: #selector(choose(_:)))
   button.tag = index + 1
   button.isBordered = false
   button.alignment = .left
   button.font = .systemFont(ofSize: 18)
   button.lineBreakMode = .byTruncatingTail
   button.toolTip = word
   button.contentTintColor = index == 0 ? .controlAccentColor : .labelColor
   button.setAccessibilityLabel("候选 \(index + 1)：\(word)")
   button.setAccessibilityIdentifier("soumao.candidate.\(index + 1)")
   buttons.append(button)
  }
  let spacing = CGFloat(buttons.count - 1) * stack.spacing + 24
  let available = max(1, bounds.width - spacing)
  let naturalWidths = buttons.map { $0.intrinsicContentSize.width + 4 }
  // Allocate spare width to long phrases without letting the window leave screen.
  var remaining = available
  var widths = Array(repeating: CGFloat(0), count: buttons.count)
  for index in buttons.indices.sorted(by: { naturalWidths[$0] < naturalWidths[$1] }) {
   let unassigned = widths.filter { $0 == 0 }.count
   widths[index] = min(naturalWidths[index], remaining / CGFloat(unassigned))
   remaining -= widths[index]
  }
  for (index, button) in buttons.enumerated() {
   button.widthAnchor.constraint(equalToConstant: widths[index]).isActive = true
   stack.addArrangedSubview(button)
  }
  let width = min(bounds.width, widths.reduce(0, +) + spacing)
  let height: CGFloat = 44
  let x = max(bounds.minX, min(anchor.minX, bounds.maxX - width))
  let below = anchor.minY - height - 5
  let y = max(bounds.minY, min(bounds.maxY - height, below < bounds.minY ? anchor.maxY + 5 : below))
  panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
  panel.contentView?.layoutSubtreeIfNeeded()
  panel.orderFrontRegardless()
 }
 @objc private func choose(_ sender: NSButton) { selection?(sender.tag) }
}
