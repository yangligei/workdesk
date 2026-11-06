#!/usr/bin/env python3
"""Render the production native status controls; no AX permissions or real data."""
from pathlib import Path
import os
import subprocess
import tempfile
import sys

repo = Path(__file__).resolve().parents[1]
source = (repo / 'Sources/Workdesk/DesignViews.swift').read_text()
parts = source[source.index('enum Desk {'):source.index('struct StatusPill:')]
parts += source[source.index('struct InlineStatus:'):source.index('struct ProjectProgress:')]
parts += (repo / 'Sources/Workdesk/StatusMenuButton.swift').read_text()
output = Path(sys.argv[1]).resolve()
program = r'''
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let states = ["待办", "进行中", "等待汇报/反馈", "阻塞", "完成"]
let content = VStack(spacing: 16) { ForEach(states, id: \.self) { value in InlineStatus(value: value, label: value) { _ in } } }.padding(24).frame(width: 220, height: 368).background(Color.white)
let host = NSHostingView(rootView: content)
let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 220,height: 368), styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = host
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
host.layoutSubtreeIfNeeded()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
let captured = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
host.cacheDisplay(in: host.bounds, to: captured)
let png = captured.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
let rep = NSBitmapImageRep(data: png)!
func pixel(_ point: NSPoint) -> NSColor {
 let scale = CGFloat(rep.pixelsWide) / host.bounds.width
 var values = [Int](repeating: 0, count: 4)
 rep.getPixel(&values, atX: Int(point.x * scale), y: Int((host.isFlipped ? point.y : host.bounds.height - point.y) * scale))
 return NSColor(srgbRed: CGFloat(values[0]) / 255, green: CGFloat(values[1]) / 255, blue: CGFloat(values[2]) / 255, alpha: 1)
}
func buttons(_ view: NSView) -> [StatusChoiceButton] { (view as? StatusChoiceButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) } }
let controls = buttons(host).sorted { $0.convert(.zero, to: host).y < $1.convert(.zero, to: host).y }
precondition(controls.count == 5)
for button in controls {
 precondition(button.bounds.size == NSSize(width: 152, height: 48))
 let labelWidth = (StatusAppearance.symbol(button.value) + " " + button.value).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).width
 precondition(11 + labelWidth < button.bounds.width - 28, "label overlaps arrow")
 let point = button.convert(NSPoint(x: 8, y: 24), to: host)
 let actual = pixel(point)
 let expected = NSColor(StatusAppearance.background(button.value)).usingColorSpace(.sRGB)!
 precondition(abs(actual.redComponent - expected.redComponent) < 0.025 && abs(actual.greenComponent - expected.greenComponent) < 0.025 && abs(actual.blueComponent - expected.blueComponent) < 0.025, "background pixels differ: \(button.value)")
 // Count actual foreground pixels, independently of the background sample.
// AppKit converts the window's display profile when encoding PNG. Allow
// that bounded conversion while still rejecting black or another state's ink.
 let ink = NSColor(StatusAppearance.foreground(button.value)).usingColorSpace(.sRGB)!
 var inkPixels = 0
 for y in 12..<36 { for x in 15..<148 {
  let p = button.convert(NSPoint(x: x, y: y), to: host)
  let c = pixel(p)
  if abs(c.redComponent - ink.redComponent) < 0.08 && abs(c.greenComponent - ink.greenComponent) < 0.08 && abs(c.blueComponent - ink.blueComponent) < 0.08 { inkPixels += 1 }
 } }
 precondition(inkPixels > 15, "foreground missing: \(button.value)")
 print("PASS pixels", button.value, "background", actual.redComponent, actual.greenComponent, actual.blueComponent, "ink samples", inkPixels)
}
final class MenuObserver { var opened = 0 }
let observer = MenuObserver()
// Observe the real menu produced by the production action without replacing it.
var selected = 0
let button = controls[0]
button.choose = { value in precondition(value == "等待汇报/反馈"); selected += 1 }
let notification = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { note in
 guard let menu = note.object as? NSMenu else { return }
 observer.opened += 1
 DispatchQueue.main.async { menu.performActionForItem(at: 2); menu.cancelTracking() }
}
for point in [NSPoint(x: 2, y: 24), NSPoint(x: 40, y: 24), NSPoint(x: 150, y: 24), NSPoint(x: 66, y: 2), NSPoint(x: 66, y: 46)] {
 let inHost = button.convert(point, to: host)
 let hit = host.hitTest(host.convert(inHost, to: host.superview))
 precondition(hit === button, "entire rectangle must hit button: \(point), got \(String(describing: hit)), expected \(button)")
 let inWindow = button.convert(point, to: nil)
 let up = NSEvent.mouseEvent(with: .leftMouseUp, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
 app.postEvent(up, atStart: true)
 let down = NSEvent.mouseEvent(with: .leftMouseDown, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
 button.mouseDown(with: down)
}
NotificationCenter.default.removeObserver(notification)
precondition(observer.opened == 5 && selected == 5, "real menu action must fire at every tested point: \(observer.opened), \(selected)")
print("PASS five real mouse press/release pairs, full-area hit tests, native menus and selection callbacks")
'''
with tempfile.TemporaryDirectory(prefix='status-render-', dir=os.environ['TMPDIR']) as temporary:
    root = Path(temporary)
    swift = root / 'main.swift'
    swift.write_text('import SwiftUI\nimport AppKit\n' + parts + program)
    subprocess.run(['swiftc', str(swift), '-o', str(root / 'check')], check=True)
    subprocess.run([str(root / 'check'), str(output)], check=True, timeout=20)
print('Native PNG:', output)
