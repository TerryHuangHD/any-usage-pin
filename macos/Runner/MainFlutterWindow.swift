import Cocoa

// The generated nib still connects this window to FlutterAppDelegate. The
// dashboard lives in the retained panel created by AppDelegate, not this window.
class MainFlutterWindow: NSWindow {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  override func awakeFromNib() {
    super.awakeFromNib()
    isExcludedFromWindowsMenu = true
    alphaValue = 0
    ignoresMouseEvents = true
    orderOut(nil)
  }

  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWindowNumber: Int) {
    super.order(.out, relativeTo: 0)
  }
}
