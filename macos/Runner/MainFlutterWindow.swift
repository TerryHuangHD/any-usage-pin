import Cocoa

// The generated nib still connects this window to FlutterAppDelegate.
// The Flutter settings view lives in AppDelegate's retained settings window.
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
