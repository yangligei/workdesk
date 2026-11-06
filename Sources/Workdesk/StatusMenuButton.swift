import AppKit
import SwiftUI

/// AppKit's borderless Menu replaces its SwiftUI label. Draw the complete
/// control ourselves and retain a native menu, keyboard action and accessibility.
struct StatusMenuButton: NSViewRepresentable {
 let value: String
 let label: String
 let choose: (String) -> Void
 func makeNSView(context: Context) -> StatusChoiceButton { StatusChoiceButton() }
 func updateNSView(_ button: StatusChoiceButton, context: Context) {
  button.value = value
  button.choose = choose
  button.setAccessibilityLabel(label)
  button.setAccessibilityValue(value)
  button.needsDisplay = true
 }
}

final class StatusChoiceButton: NSButton {
 var value = "待办"
 var choose: (String) -> Void = { _ in }
 override var intrinsicContentSize: NSSize { NSSize(width: 152, height: 48) }
 override init(frame: NSRect) {
  super.init(frame: frame)
  isBordered = false
  title = ""
  target = self
  action = #selector(openChoices)
  setButtonType(.momentaryChange)
  setAccessibilityRole(.popUpButton)
 }
 required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
 override func draw(_ dirtyRect: NSRect) {
  NSColor(StatusAppearance.background(value)).setFill()
  NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
  let ink = NSColor(StatusAppearance.foreground(value))
  let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: ink]
  let text = StatusAppearance.symbol(value) + " " + value
  let size = text.size(withAttributes: attributes)
  text.draw(at: NSPoint(x: 11, y: (bounds.height - size.height) / 2), withAttributes: attributes)
  ink.setStroke()
  let chevron = NSBezierPath()
  let edgeY: CGFloat = isFlipped ? 22 : 26
  let tipY: CGFloat = isFlipped ? 25 : 23
  chevron.move(to: NSPoint(x: bounds.width - 22, y: edgeY))
  chevron.line(to: NSPoint(x: bounds.width - 19, y: tipY))
  chevron.line(to: NSPoint(x: bounds.width - 16, y: edgeY))
  chevron.lineWidth = 1
  chevron.stroke()
  if isHighlighted { NSColor.black.withAlphaComponent(0.06).setFill(); NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill() }
  if window?.firstResponder === self {
   NSColor.keyboardFocusIndicatorColor.setStroke()
   let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
   ring.lineWidth = 2
   ring.stroke()
  }
 }
 @objc func openChoices() {
  let menu = NSMenu()
  for status in ["待办", "进行中", "等待汇报/反馈", "阻塞", "完成"] {
   let item = NSMenuItem(title: status, action: #selector(selectChoice(_:)), keyEquivalent: "")
   item.target = self
   item.state = status == value ? .on : .off
   menu.addItem(item)
  }
  menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: self)
 }
 @objc private func selectChoice(_ sender: NSMenuItem) { choose(sender.title) }
}
