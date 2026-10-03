import Cocoa
import CoreFoundation
import FlutterMacOS

private final class DashboardPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

private struct StatusLayer: Equatable {
  let text: String?
  let showBar: Bool
  let fraction: Double?
  let status: String
}

private struct StatusPin: Equatable {
  let id: String
  let provider: String
  let title: String
  let tooltip: String
  let showIcon: Bool
  let label: String
  let labelWidth: Int
  let color: String
  let status: String
  let layers: [StatusLayer]

  init?(_ value: [String: Any]) {
    guard let id = value["id"] as? String, !id.isEmpty,
          let provider = value["provider"] as? String,
          let title = value["title"] as? String,
          let tooltip = value["tooltip"] as? String,
          let showIcon = value["showIcon"] as? Bool,
          let label = value["label"] as? String,
          let labelWidth = value["labelWidth"] as? Int, labelWidth >= 0,
          let color = value["color"] as? String,
          let pinStatus = value["status"] as? String,
          let rawLayers = value["layers"] as? [[String: Any]],
          rawLayers.count <= 2 else { return nil }
    var layers: [StatusLayer] = []
    layers.reserveCapacity(rawLayers.count)
    for raw in rawLayers {
      guard let showBar = raw["showBar"] as? NSNumber,
            CFGetTypeID(showBar) == CFBooleanGetTypeID(),
            let status = raw["status"] as? String else { return nil }
      let text: String?
      if let value = raw["text"], !(value is NSNull) {
        guard let string = value as? String else { return nil }
        text = string
      } else {
        text = nil
      }
      var fraction: Double?
      if let number = raw["fraction"] as? NSNumber {
        guard CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        fraction = min(1, max(0, number.doubleValue))
      } else if let value = raw["fraction"], !(value is NSNull) {
        return nil
      }
      if text != nil || showBar.boolValue {
        layers.append(StatusLayer(
          text: text, showBar: showBar.boolValue, fraction: fraction, status: status))
      }
    }
    self.id = id
    self.provider = provider
    self.title = title
    self.tooltip = tooltip
    self.showIcon = showIcon
    self.label = label
    self.labelWidth = labelWidth
    self.color = color
    self.status = pinStatus
    self.layers = layers
  }
}

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  private var engine: FlutterEngine?
  private var flutterController: FlutterViewController?
  private var desktopChannel: FlutterMethodChannel?
  private var panel: DashboardPanel?
  private var launcher: NSStatusItem?
  private var pinItems: [String: NSStatusItem] = [:]
  private var pins: [StatusPin] = []
  private weak var anchorButton: NSStatusBarButton?
  private var localMonitor: Any?
  private var globalMonitor: Any?
  private var ready = false
  private var requestedOpen = ProcessInfo.processInfo.arguments.contains("--show")
  private var pendingWake = false
  private var terminationRequested = false
  private var terminationReplySent = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    mainFlutterWindow?.orderOut(nil)
    mainFlutterWindow?.close()
    createLauncher()

    let engine = FlutterEngine(
      name: "AnyUsagePin", project: nil, allowHeadlessExecution: true)
    self.engine = engine
    // Install the handler before either running Dart or attaching a view that
    // could start the engine from viewWillAppear.
    let channel = FlutterMethodChannel(
      name: "dev.anyusagepin/desktop", binaryMessenger: engine.binaryMessenger)
    desktopChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Desktop is unavailable.", details: nil))
        return
      }
      self.handle(call, result: result)
    }

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    flutterController = controller
    RegisterGeneratedPlugins(registry: controller)
    let panel = DashboardPanel(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered, defer: false)
    panel.title = "AnyUsagePin"
    panel.titleVisibility = .hidden
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = false
    panel.hidesOnDeactivate = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.minSize = NSSize(width: 440, height: 440)
    panel.delegate = self
    self.panel = panel
    mainFlutterWindow = panel
    panel.contentViewController = controller
    panel.setContentSize(NSSize(width: 620, height: 680))
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      panel.standardWindowButton(button)?.isHidden = true
    }
    installObservers()
    if !engine.run(withEntrypoint: nil) {
      let alert = NSAlert()
      alert.messageText = "AnyUsagePin could not start"
      alert.informativeText = "The Flutter engine could not be started. Please relaunch the application."
      alert.runModal()
      NSApp.terminate(nil)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "desktop.ready":
      ready = true
      let arguments = call.arguments as? [String: Any]
      let shouldOpen = requestedOpen || (arguments?["open"] as? Bool == true)
      result(nil)
      if pendingWake {
        pendingWake = false
        desktopChannel?.invokeMethod("desktop.wake", arguments: nil)
      }
      if shouldOpen {
        // Let AppKit lay out the status item before reading its screen anchor.
        DispatchQueue.main.async { [weak self] in self?.showPanel() }
      }
    case "menu.update":
      guard let arguments = call.arguments as? [String: Any],
            let values = arguments["pins"] as? [[String: Any]] else {
        result(FlutterError(code: "invalid_arguments", message: "Expected a pins list.", details: nil))
        return
      }
      let newPins = values.compactMap(StatusPin.init)
      guard newPins.count == values.count,
            Set(newPins.map(\.id)).count == newPins.count else {
        result(FlutterError(code: "invalid_arguments", message: "Invalid pin configuration.", details: nil))
        return
      }
      updatePins(newPins)
      result(nil)
    case "panel.show":
      showPanel()
      result(nil)
    case "panel.hide":
      requestedOpen = false
      hidePanel()
      result(nil)
    case "app.quit":
      result(nil)
      NSApp.terminate(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func createLauncher() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    launcher = item
    if let button = item.button {
      button.image = StatusArtwork.launcherImage
      button.image?.isTemplate = true
      button.toolTip = "AnyUsagePin"
      button.setAccessibilityLabel("Open AnyUsagePin")
      configureButton(button)
    }
  }

  private func configureButton(_ button: NSStatusBarButton) {
    button.target = self
    button.action = #selector(statusClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  private func updatePins(_ newPins: [StatusPin]) {
    let oldPins = pins
    launcher?.isVisible = newPins.isEmpty
    if oldPins.map(\.id) != newPins.map(\.id) {
      anchorButton = nil
      for item in pinItems.values { NSStatusBar.system.removeStatusItem(item) }
      pinItems.removeAll(keepingCapacity: true)
      // New AppKit items appear to the left of existing items. Reverse creation
      // keeps the explicit pin sequence left-to-right.
      for pin in newPins.reversed() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        pinItems[pin.id] = item
        if let button = item.button { configureButton(button) }
      }
      pins = newPins
      redrawPins()
      return
    }
    pins = newPins
    for (old, new) in zip(oldPins, newPins) where old != new {
      let redraw = old.provider != new.provider ||
        old.showIcon != new.showIcon || old.label != new.label ||
        old.labelWidth != new.labelWidth || old.color != new.color ||
        old.status != new.status || old.layers != new.layers
      render(new, redraw: redraw)
    }
  }

  private func redrawPins() {
    for pin in pins { render(pin) }
  }

  private func render(_ pin: StatusPin, redraw: Bool = true) {
    guard let item = pinItems[pin.id], let button = item.button else { return }
    if redraw || button.image == nil {
      button.effectiveAppearance.performAsCurrentDrawingAppearance {
        let image = StatusArtwork.image(for: pin)
        item.length = image.size.width
        button.image = image
        button.imagePosition = .imageOnly
      }
    }
    button.toolTip = pin.tooltip
    button.setAccessibilityLabel(pin.title)
    button.setAccessibilityValue(pin.tooltip)
  }

  @objc private func statusClicked(_ sender: NSStatusBarButton) {
    anchorButton = sender
    if NSApp.currentEvent?.type == .rightMouseUp ||
        NSApp.currentEvent?.modifierFlags.contains(.control) == true {
      let menu = NSMenu()
      let open = NSMenuItem(title: "Open", action: #selector(openFromMenu), keyEquivalent: "")
      open.target = self
      menu.addItem(open)
      menu.addItem(.separator())
      let quit = NSMenuItem(title: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q")
      quit.target = self
      menu.addItem(quit)
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
    } else {
      showPanel()
    }
  }

  @objc private func openFromMenu() { showPanel() }
  @objc private func quitFromMenu() { NSApp.terminate(nil) }

  private func showPanel() {
    requestedOpen = true
    guard ready, let panel = panel else { return }
    let wasVisible = panel.isVisible
    if !wasVisible { positionPanel(panel) }
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    if let inputView = flutterController?.view.subviews.first(where: { $0.acceptsFirstResponder }) {
      panel.makeFirstResponder(inputView)
    }
    if !wasVisible { desktopChannel?.invokeMethod("desktop.opened", arguments: nil) }
  }

  private func positionPanel(_ panel: NSPanel) {
    let defaultButton = pins.first.flatMap { pinItems[$0.id]?.button } ?? launcher?.button
    let button = anchorButton ?? defaultButton
    let screen = button?.window?.screen ?? NSScreen.main
    guard let screen = screen else { panel.center(); return }
    let visible = screen.visibleFrame
    var frame = panel.frame
    frame.size.width = min(frame.width, visible.width)
    frame.size.height = min(frame.height, visible.height - 12)
    var centerX = visible.midX
    if let button = button, let window = button.window {
      let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
      if anchor.width > 0 && anchor.height > 0 &&
          anchor.midY >= screen.frame.maxY - NSStatusBar.system.thickness &&
          screen.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) {
        centerX = anchor.midX
      }
    }
    frame.origin.x = max(visible.minX, min(centerX - frame.width / 2, visible.maxX - frame.width))
    frame.origin.y = visible.maxY - frame.height - 6
    panel.setFrame(frame, display: false)
  }

  private func hidePanel() {
    guard let panel = panel, panel.isVisible else { return }
    requestedOpen = false
    panel.orderOut(nil)
    if ready { desktopChannel?.invokeMethod("desktop.closed", arguments: nil) }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hidePanel()
    return false
  }

  func windowDidResignKey(_ notification: Notification) { hidePanel() }

  private func installObservers() {
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(workspaceWoke(_:)),
      name: NSWorkspace.didWakeNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(appDeactivated(_:)),
      name: NSApplication.didResignActiveNotification, object: nil)
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(appearanceChanged(_:)),
      name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    localMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
        guard let self = self, let panel = self.panel, panel.isVisible else { return event }
        if event.type == .keyDown {
          if event.keyCode == 53 {
            self.hidePanel()
            return nil
          }
        } else if event.window !== panel {
          self.hidePanel()
        }
        return event
      }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hidePanel() }
  }

  @objc private func workspaceWoke(_ notification: Notification) {
    if ready {
      desktopChannel?.invokeMethod("desktop.wake", arguments: nil)
    } else {
      pendingWake = true
    }
  }

  @objc private func appDeactivated(_ notification: Notification) { hidePanel() }
  @objc private func appearanceChanged(_ notification: Notification) { redrawPins() }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    showPanel()
    return false
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard ready, let channel = desktopChannel else { return .terminateNow }
    if terminationRequested { return .terminateLater }
    terminationRequested = true
    let reply = { [weak self] in
      guard let self = self, !self.terminationReplySent else { return }
      self.terminationReplySent = true
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    channel.invokeMethod("desktop.terminating", arguments: nil) { _ in reply() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reply)
    return .terminateLater
  }

  override func applicationWillTerminate(_ notification: Notification) {
    if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
    if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
    DistributedNotificationCenter.default().removeObserver(self)
    desktopChannel?.setMethodCallHandler(nil)
    engine?.shutDownEngine()
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }
}

private enum StatusArtwork {
  private static let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
  private static let singleFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
  private static let doubleFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
  private static let labelParagraph: NSParagraphStyle = {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    return paragraph
  }()
  private static let warningText: NSString = "!"
  private static let unknownText: NSString = "?"
  private static let barWidth: CGFloat = 32
  private static let barGap: CGFloat = 6
  private static let warningGap: CGFloat = 3
  private static var logos: [String: NSImage] = [:]
  static let launcherImage = NSImage(systemSymbolName: "chart.bar", accessibilityDescription: nil)

  private static func logo(for provider: String) -> NSImage? {
    if let image = logos[provider] { return image }
    switch provider {
    case "anthropic", "openai-codex", "google-antigravity", "xai-oauth", "cursor": break
    default:
      return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
    }
    let key = FlutterDartProject.lookupKey(forAsset: "assets/providers/\(provider).png")
    let url = Bundle.main.bundleURL.appendingPathComponent(key)
    guard let image = NSImage(contentsOf: url) else { return nil }
    logos[provider] = image
    return image
  }

  private static func customColor(_ value: String) -> NSColor? {
    guard value.count == 7, value.first == "#",
          let rgb = UInt32(value.dropFirst(), radix: 16) else { return nil }
    return NSColor(
      srgbRed: CGFloat((rgb >> 16) & 255) / 255,
      green: CGFloat((rgb >> 8) & 255) / 255,
      blue: CGFloat(rgb & 255) / 255, alpha: 1)
  }

  static func image(for pin: StatusPin) -> NSImage {
    let selectedColor = customColor(pin.color)
    let color = selectedColor ?? .black
    let layers = pin.layers
    let font = layers.count == 2 ? doubleFont : singleFont
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let labelAttributes: [NSAttributedString.Key: Any] = [
      .font: labelFont, .foregroundColor: color, .paragraphStyle: labelParagraph,
    ]
    let labelWidth: CGFloat = pin.label.isEmpty ? 0 : CGFloat(pin.labelWidth)
    let hasRowWarning = layers.contains { $0.status != "ok" }
    let hasGlobalWarning = pin.status != "ok" && !hasRowWarning
    let warningWidth: CGFloat = hasRowWarning || hasGlobalWarning
      ? ceil(warningText.size(withAttributes: attributes).width) : 0
    let hasUnknownBar = layers.contains { $0.showBar && $0.fraction == nil }
    let unknownWidth: CGFloat = hasUnknownBar
      ? ceil(unknownText.size(withAttributes: attributes).width) : 0
    let trackColor = layers.contains { $0.showBar && $0.fraction != nil }
      ? color.withAlphaComponent(0.25) : nil
    var rowsWidth: CGFloat = 0
    for layer in layers {
      let warns = layer.status != "ok"
      var width: CGFloat = layer.showBar ? barWidth : 0
      if layer.showBar && (layer.text != nil || warns) { width += barGap }
      if warns {
        width += warningWidth
        if layer.text != nil { width += warningGap }
      }
      if let text = layer.text {
        width += ceil((text as NSString).size(withAttributes: attributes).width)
      }
      rowsWidth = max(rowsWidth, width)
    }
    let iconWidth: CGFloat = pin.showIcon ? 18 : 0
    let labelGap: CGFloat = labelWidth > 0 && rowsWidth > 0 ? 5 : 0
    let globalWarningGap: CGFloat = hasGlobalWarning && (rowsWidth > 0 || labelWidth > 0)
      ? warningGap : 0
    let globalWarningWidth: CGFloat = hasGlobalWarning ? globalWarningGap + warningWidth : 0
    let size = NSSize(
      width: max(22, 4 + iconWidth + labelWidth + labelGap + rowsWidth + globalWarningWidth),
      height: 22)
    let image = NSImage(size: size)
    image.lockFocus()
    var x: CGFloat = 2
    if pin.showIcon {
      if let logo = logo(for: pin.provider) {
        let scale = min(14 / logo.size.width, 14 / logo.size.height)
        let width = logo.size.width * scale
        let height = logo.size.height * scale
        let rect = NSRect(x: x + (14 - width) / 2, y: (22 - height) / 2,
                          width: width, height: height)
        logo.draw(in: rect)
        if pin.provider != "anthropic" && pin.provider != "google-antigravity" {
          (selectedColor == nil ? NSColor.black : NSColor.labelColor).setFill()
          rect.fill(using: .sourceAtop)
        }
      }
      x += iconWidth
    }
    if labelWidth > 0 {
      (pin.label as NSString).draw(
        in: NSRect(x: x, y: 4, width: labelWidth, height: 14),
        withAttributes: labelAttributes)
      x += labelWidth + labelGap
    }
    for (index, layer) in layers.enumerated() {
      let y: CGFloat = layers.count == 2 ? (index == 0 ? 11 : 1) : 4
      var rowX = x
      let warns = layer.status != "ok"
      if layer.showBar {
        if let fraction = layer.fraction {
          let track = NSRect(x: rowX, y: y + 3, width: barWidth, height: 4)
          trackColor?.setFill()
          NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
          if fraction > 0 {
            color.setFill()
            let filled = NSRect(
              x: track.minX, y: track.minY,
              width: track.width * CGFloat(fraction), height: track.height)
            NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
          }
        } else {
          // An outlined track with a question mark is unknown, not a valid zero.
          let track = NSRect(x: rowX, y: y + 1, width: barWidth, height: 8)
          color.setStroke()
          NSBezierPath(
            roundedRect: track.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).stroke()
          unknownText.draw(
            at: NSPoint(x: rowX + (barWidth - unknownWidth) / 2, y: y),
            withAttributes: attributes)
        }
        rowX += barWidth
        if layer.text != nil || warns { rowX += barGap }
      }
      if warns {
        warningText.draw(at: NSPoint(x: rowX, y: y), withAttributes: attributes)
        rowX += warningWidth
        if layer.text != nil { rowX += warningGap }
      }
      if let text = layer.text {
        (text as NSString).draw(at: NSPoint(x: rowX, y: y), withAttributes: attributes)
      }
    }
    if hasGlobalWarning {
      warningText.draw(
        at: NSPoint(x: x + rowsWidth + globalWarningGap, y: 4), withAttributes: attributes)
    }
    image.unlockFocus()
    // NSStatusBarButton applies the menu bar's own tint, independent of app appearance.
    image.isTemplate = selectedColor == nil
    return image
  }
}
