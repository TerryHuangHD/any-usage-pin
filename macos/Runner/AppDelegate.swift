import Cocoa
import CoreFoundation
import FlutterMacOS
import ServiceManagement

private final class GlassSurface: NSView {
  let content = NSView()

  init(cornerRadius: CGFloat) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.cornerRadius = cornerRadius
    layer?.masksToBounds = true
    let effect: NSView
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.style = .regular
      glass.cornerRadius = cornerRadius
      glass.contentView = content
      effect = glass
    } else {
      let material = NSVisualEffectView()
      material.material = .popover
      material.blendingMode = .behindWindow
      material.state = .active
      if cornerRadius > 0 {
        let size = NSSize(width: cornerRadius * 2 + 1, height: cornerRadius * 2 + 1)
        let mask = NSImage(size: size, flipped: false) { rect in
          NSColor.white.setFill()
          NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
          return true
        }
        mask.capInsets = NSEdgeInsets(
          top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        mask.resizingMode = .stretch
        material.maskImage = mask
      }
      material.addSubview(content)
      effect = material
    }
    addSubview(effect)
    effect.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      effect.leadingAnchor.constraint(equalTo: leadingAnchor),
      effect.trailingAnchor.constraint(equalTo: trailingAnchor),
      effect.topAnchor.constraint(equalTo: topAnchor),
      effect.bottomAnchor.constraint(equalTo: bottomAnchor),
      content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
      content.topAnchor.constraint(equalTo: effect.topAnchor),
      content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class UsagePanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

private struct UsageLimit: Equatable {
  let id: String
  let label: String
  let value: String
  let reset: String
  let fraction: Double?
  let status: String
  let warning: String?

  init(_ data: [String: Any]) {
    id = data["id"] as? String ?? ""
    label = data["label"] as? String ?? ""
    value = data["value"] as? String ?? "無資料"
    reset = data["reset"] as? String ?? ""
    let number = (data["fraction"] as? NSNumber)?.doubleValue
    fraction = number.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
    status = data["status"] as? String ?? "missing"
    warning = data["warning"] as? String
  }
}

private struct UsageAccount: Equatable {
  let id: String
  let provider: String
  let name: String
  let label: String
  let plan: String?
  let organization: String?
  let age: String
  let pinned: Bool
  let warning: String?
  let limits: [UsageLimit]
  let emptyMessage: String
  let needsAttention: Bool

  var hasProblem: Bool { needsAttention }

  init(_ data: [String: Any]) {
    id = data["id"] as? String ?? ""
    let providerID = data["provider"] as? String ?? ""
    provider = providerID
    name = data["name"] as? String ?? providerID
    label = data["label"] as? String ?? ""
    plan = data["plan"] as? String
    organization = data["organization"] as? String
    age = data["age"] as? String ?? ""
    pinned = data["pinned"] as? Bool ?? false
    warning = data["warning"] as? String
    limits = (data["limits"] as? [[String: Any]] ?? []).map(UsageLimit.init)
    emptyMessage = data["emptyMessage"] as? String ?? "沒有可用的配額資料"
    needsAttention = data["needsAttention"] as? Bool ?? false
  }
}

private enum UsageStyle {
  static let cardColor = NSColor(name: "UsageCard") { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(srgbRed: 34 / 255, green: 34 / 255, blue: 34 / 255, alpha: 0.90)
      : NSColor.white.withAlphaComponent(0.82)
  }
  static let cardBorder = NSColor(name: "UsageCardBorder") { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor.white.withAlphaComponent(0.10)
      : NSColor.black.withAlphaComponent(0.08)
  }

  static func text(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: "")
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = .labelColor
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
  }

  static func vertical(_ spacing: CGFloat) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }

  static func add(_ child: NSView, to stack: NSStackView) {
    stack.addArrangedSubview(child)
    child.translatesAutoresizingMaskIntoConstraints = false
    child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
  }

  static func statusColor(_ status: String) -> NSColor {
    switch status {
    case "error": return .systemRed
    case "stale": return .systemOrange
    case "missing": return .secondaryLabelColor
    default: return .systemBlue
    }
  }
}

private final class UsageDocumentView: NSView {
  override var isFlipped: Bool { true }
}

private final class UsageProgressView: NSView {
  var fraction: Double? {
    didSet { needsDisplay = true }
  }
  var status = "missing" {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    NSColor.quaternaryLabelColor.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
    guard let fraction = fraction else { return }
    let fill = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(fraction), height: bounds.height)
    let color = status == "ok" && fraction <= 0.1 ? NSColor.systemRed :
      status == "ok" && fraction <= 0.25 ? NSColor.systemOrange : UsageStyle.statusColor(status)
    color.setFill()
    NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

private final class UsageLimitView: NSView {
  private let stack = UsageStyle.vertical(5)
  private let heading = NSStackView()
  private let title = UsageStyle.text(12, weight: .medium)
  private let value = UsageStyle.text(16, weight: .semibold)
  private let progress = UsageProgressView()
  private let reset = UsageStyle.text(11)
  private let warning = UsageStyle.text(11, weight: .medium)
  private var previous: UsageLimit?
  private var previousCompact = false
  private var previousTable = false
  private lazy var tableValueWidth = value.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.25)
  private lazy var tableResetWidth = reset.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.36)
  private lazy var resetFullWidth = reset.widthAnchor.constraint(equalTo: stack.widthAnchor)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    heading.orientation = .horizontal
    heading.distribution = .fill
    heading.alignment = .firstBaseline
    heading.spacing = 8
    heading.addArrangedSubview(title)
    heading.addArrangedSubview(value)
    title.setContentHuggingPriority(.defaultLow, for: .horizontal)
    value.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
    value.alignment = .right
    value.setContentHuggingPriority(.required, for: .horizontal)
    value.setContentCompressionResistancePriority(.required, for: .horizontal)
    UsageStyle.add(heading, to: stack)
    value.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.65).isActive = true
    UsageStyle.add(progress, to: stack)
    progress.heightAnchor.constraint(equalToConstant: 6).isActive = true
    progress.setAccessibilityElement(true)
    progress.setAccessibilityRole(.progressIndicator)
    stack.addArrangedSubview(reset)
    reset.translatesAutoresizingMaskIntoConstraints = false
    resetFullWidth.isActive = true
    reset.textColor = .secondaryLabelColor
    UsageStyle.add(warning, to: stack)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(_ limit: UsageLimit, compact: Bool, table: Bool) {
    guard previous != limit || previousCompact != compact || previousTable != table else { return }
    if previous == nil || previousTable != table {
      if table {
        stack.removeArrangedSubview(reset)
        reset.removeFromSuperview()
        heading.addArrangedSubview(reset)
      } else if previousTable {
        heading.removeArrangedSubview(reset)
        reset.removeFromSuperview()
        stack.insertArrangedSubview(reset, at: 2)
      }
      tableValueWidth.isActive = table
      tableResetWidth.isActive = table
      resetFullWidth.isActive = !table
      progress.isHidden = table
    }
    previous = limit
    previousCompact = compact
    previousTable = table
    stack.spacing = compact ? 3 : 5
    title.stringValue = limit.label
    value.stringValue = limit.value
    value.font = .monospacedDigitSystemFont(ofSize: compact ? 13 : 16, weight: .semibold)
    value.textColor = limit.status == "ok" ? .labelColor : UsageStyle.statusColor(limit.status)
    progress.fraction = limit.fraction
    progress.status = limit.status
    progress.isHidden = table || limit.fraction == nil
    progress.setAccessibilityLabel("\(limit.label), \(limit.status)")
    progress.setAccessibilityValue(limit.value)
    reset.stringValue = limit.reset
    reset.isHidden = limit.reset.isEmpty
    let message: String
    if let detail = limit.warning, !detail.isEmpty {
      message = detail
    } else {
      switch limit.status {
      case "stale": message = "舊資料 · 待來源更新"
      case "error": message = "查詢異常 · 保留已知資料"
      case "missing": message = "缺少配額數值"
      default: message = ""
      }
    }
    warning.stringValue = message
    warning.textColor = UsageStyle.statusColor(limit.status == "ok" ? "stale" : limit.status)
    warning.isHidden = message.isEmpty
  }
}

private final class UsageAccountView: NSView {
  private let stack = UsageStyle.vertical(12)
  private let logo = NSImageView()
  private let name = UsageStyle.text(13, weight: .semibold)
  private let label = UsageStyle.text(12)
  private let metadata = UsageStyle.text(11)
  private let warning = UsageStyle.text(11, weight: .medium)
  private let noData = UsageStyle.text(12)
  private let limitsStack = UsageStyle.vertical(12)
  private let tableHeader = NSStackView()
  private var limitViews: [String: UsageLimitView] = [:]
  private var limitIDs: [String] = []
  private var padding: [NSLayoutConstraint] = []
  private var previous: UsageAccount?
  private var previousDense = false
  private var previousTable = false
  private var table = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.borderWidth = 1
    addSubview(stack)
    padding = [
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 12),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 12),
    ]
    NSLayoutConstraint.activate(padding)
    let header = NSStackView()
    header.orientation = .horizontal
    header.distribution = .fill
    header.alignment = .top
    header.spacing = 9
    logo.imageScaling = .scaleProportionallyUpOrDown
    logo.contentTintColor = .labelColor
    logo.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      logo.widthAnchor.constraint(equalToConstant: 24),
      logo.heightAnchor.constraint(equalToConstant: 24),
    ])
    header.addArrangedSubview(logo)
    let identity = UsageStyle.vertical(3)
    UsageStyle.add(name, to: identity)
    UsageStyle.add(label, to: identity)
    UsageStyle.add(metadata, to: identity)
    metadata.textColor = .secondaryLabelColor
    header.addArrangedSubview(identity)
    UsageStyle.add(header, to: stack)
    identity.widthAnchor.constraint(equalTo: header.widthAnchor, constant: -33).isActive = true
    UsageStyle.add(warning, to: stack)
    warning.textColor = .systemOrange
    tableHeader.orientation = .horizontal
    tableHeader.distribution = .fill
    tableHeader.alignment = .firstBaseline
    tableHeader.spacing = 8
    let windowTitle = UsageStyle.text(10)
    windowTitle.stringValue = "窗口"
    windowTitle.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let remainingTitle = UsageStyle.text(10)
    remainingTitle.stringValue = "剩餘"
    remainingTitle.alignment = .right
    let resetTitle = UsageStyle.text(10)
    resetTitle.stringValue = "重置倒數"
    for field in [windowTitle, remainingTitle, resetTitle] {
      field.textColor = .secondaryLabelColor
      tableHeader.addArrangedSubview(field)
    }
    NSLayoutConstraint.activate([
      remainingTitle.widthAnchor.constraint(equalTo: tableHeader.widthAnchor, multiplier: 0.25),
      resetTitle.widthAnchor.constraint(equalTo: tableHeader.widthAnchor, multiplier: 0.36),
    ])
    UsageStyle.add(limitsStack, to: stack)
    UsageStyle.add(noData, to: stack)
    noData.stringValue = "沒有可用的配額資料"
    noData.textColor = .secondaryLabelColor
    updateColors()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = UsageStyle.cardColor.cgColor
      layer?.borderColor = UsageStyle.cardBorder.cgColor
      layer?.cornerRadius = 12
    }
  }

  func update(_ account: UsageAccount, dense: Bool, table: Bool) {
    guard previous != account || previousDense != dense || previousTable != table else { return }
    let tableChanged = previousTable != table
    previous = account
    previousDense = dense
    previousTable = table
    self.table = table
    updateColors()
    let compact = dense || table
    padding.forEach { $0.constant = compact ? 9 : 12 }
    stack.spacing = compact ? 8 : 12
    limitsStack.spacing = compact ? 9 : 14
    logo.image = StatusArtwork.logo(for: account.provider)
    logo.setAccessibilityLabel(account.name)
    name.stringValue = account.name + (account.pinned ? " · 已釘選" : "")
    label.stringValue = account.label
    label.isHidden = account.label.isEmpty
    metadata.stringValue = [account.plan, account.organization, account.age]
      .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    metadata.isHidden = metadata.stringValue.isEmpty
    warning.stringValue = account.warning ?? ""
    warning.isHidden = warning.stringValue.isEmpty
    noData.isHidden = !account.limits.isEmpty
    noData.stringValue = account.emptyMessage
    limitsStack.isHidden = account.limits.isEmpty
    let ids = account.limits.map(\.id)
    if ids != limitIDs || tableChanged {
      for view in limitsStack.arrangedSubviews {
        limitsStack.removeArrangedSubview(view)
        view.removeFromSuperview()
      }
      if table { UsageStyle.add(tableHeader, to: limitsStack) }
      limitViews = limitViews.filter { ids.contains($0.key) }
      for limit in account.limits {
        let view = limitViews[limit.id] ?? UsageLimitView()
        limitViews[limit.id] = view
        UsageStyle.add(view, to: limitsStack)
      }
      limitIDs = ids
    }
    for limit in account.limits {
      limitViews[limit.id]?.update(limit, compact: compact, table: table)
    }
  }
}

private final class UsagePanelController: NSViewController {
  var onRefresh: (() -> Void)?
  var onSettings: (() -> Void)?
  private let scroll = NSScrollView()
  private let document = UsageDocumentView()
  private let content = UsageStyle.vertical(12)
  private let accountsStack = UsageStyle.vertical(10)
  private let empty = UsageStyle.text(13)
  private let focusNotice = UsageStyle.text(12)
  private let notices = UsageStyle.text(11)
  private let expand = NSButton(title: "展開全部帳號", target: nil, action: nil)
  private let refresh = NSButton()
  private let spinner = NSProgressIndicator()
  private let footerStatus = NSTextField(labelWithString: "等待來源資料")
  private var accounts: [UsageAccount] = []
  private var accountViews: [String: UsageAccountView] = [:]
  private var visibleIDs: [String] = []
  private var focusExpanded = false
  private var layout = "cards"
  private var dense = false
  private var emptyMessage = "等待來源資料"

  override func loadView() {
    let shell = GlassSurface(cornerRadius: 16)
    shell.widthAnchor.constraint(equalToConstant: 380).isActive = true
    let root = shell.content
    view = shell

    let title = UsageStyle.text(14, weight: .semibold)
    title.stringValue = "訂閱用量"
    title.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(title)
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.borderType = .noBorder
    scroll.scrollerStyle = .overlay
    scroll.contentView.drawsBackground = false
    scroll.contentView.backgroundColor = .clear
    scroll.backgroundColor = .clear
    root.addSubview(scroll)
    document.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = document
    document.addSubview(content)
    NSLayoutConstraint.activate([
      document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
      content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
      content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
      content.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
      content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
    ])
    UsageStyle.add(focusNotice, to: content)
    focusNotice.textColor = .secondaryLabelColor
    UsageStyle.add(expand, to: content)
    expand.bezelStyle = .rounded
    expand.target = self
    expand.action = #selector(toggleFocus)
    UsageStyle.add(empty, to: content)
    empty.textColor = .secondaryLabelColor
    UsageStyle.add(accountsStack, to: content)
    UsageStyle.add(notices, to: content)
    notices.textColor = .systemOrange
    focusNotice.isHidden = true
    expand.isHidden = true
    notices.isHidden = true
    empty.stringValue = emptyMessage

    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(separator)
    let footer = NSStackView()
    footer.orientation = .horizontal
    footer.distribution = .fill
    footer.alignment = .centerY
    footer.spacing = 8
    footer.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(footer)
    refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "更新用量")
    refresh.bezelStyle = .texturedRounded
    refresh.target = self
    refresh.action = #selector(refreshUsage)
    refresh.toolTip = "更新用量"
    refresh.setAccessibilityLabel("更新用量")
    footer.addArrangedSubview(refresh)
    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    spinner.isHidden = true
    footer.addArrangedSubview(spinner)
    footerStatus.font = .systemFont(ofSize: 11)
    footerStatus.textColor = .secondaryLabelColor
    footerStatus.lineBreakMode = .byTruncatingTail
    footerStatus.setContentHuggingPriority(.defaultLow, for: .horizontal)
    footerStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    footer.addArrangedSubview(footerStatus)
    let settings = NSButton()
    settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "開啟設定")
    settings.bezelStyle = .texturedRounded
    settings.target = self
    settings.action = #selector(openSettings)
    settings.toolTip = "設定"
    settings.setAccessibilityLabel("開啟設定")
    footer.addArrangedSubview(settings)
    NSLayoutConstraint.activate([
      title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
      title.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
      scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 9),
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -4),
      separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      separator.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -9),
      footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
      footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
      footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
      footer.heightAnchor.constraint(equalToConstant: 28),
      refresh.widthAnchor.constraint(equalToConstant: 30),
      settings.widthAnchor.constraint(equalToConstant: 30),
      spinner.widthAnchor.constraint(equalToConstant: 16),
      spinner.heightAnchor.constraint(equalToConstant: 16),
    ])
  }

  func update(_ data: [String: Any]) {
    _ = view
    switch data["theme"] as? String {
    case "light": view.appearance = NSAppearance(named: .aqua)
    case "dark": view.appearance = NSAppearance(named: .darkAqua)
    default: view.appearance = nil
    }
    accounts = (data["accounts"] as? [[String: Any]] ?? []).map(UsageAccount.init)
    layout = data["layout"] as? String ?? "cards"
    dense = data["dense"] as? Bool ?? false
    content.spacing = dense ? 8 : 12
    accountsStack.spacing = dense || layout == "table" ? 6 : 10
    emptyMessage = data["emptyMessage"] as? String ?? "沒有可查詢的帳號"
    let loading = data["loading"] as? Bool ?? false
    let initialized = data["initialized"] as? Bool ?? false
    footerStatus.stringValue = data["footer"] as? String ??
      (loading ? "向 OMP 查詢中…" : initialized ? "用量已更新" : "等待來源資料")
    footerStatus.toolTip = footerStatus.stringValue
    refresh.isEnabled = initialized && !loading
    spinner.isHidden = !loading
    if loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    notices.stringValue = (data["notices"] as? [String] ?? []).joined(separator: "\n\n")
    notices.isHidden = notices.stringValue.isEmpty
    renderAccounts()
  }

  private func renderAccounts() {
    view.layoutSubtreeIfNeeded()
    let oldY = scroll.contentView.bounds.minY
    let anchor = visibleIDs.first { id in
      guard let card = accountViews[id] else { return false }
      return card.convert(card.bounds, to: document).maxY > oldY
    }
    let anchorOffset = anchor.flatMap { accountViews[$0] }
      .map { oldY - $0.convert($0.bounds, to: document).minY }
    let focused = layout == "focus"
    let visible = focused && !focusExpanded ? accounts.filter(\.pinned) : accounts
    let unpinned = accounts.filter { !$0.pinned }
    let problems = unpinned.filter(\.hasProblem).count
    focusNotice.isHidden = !focused || unpinned.isEmpty
    if problems > 0 {
      let detail = focusExpanded ? "" : "請展開全部帳號查看。"
      focusNotice.stringValue = "\(problems) 個未釘選帳號需注意。\(detail)"
    } else {
      focusNotice.stringValue = focusExpanded ? "已展開全部帳號。" : "只顯示已釘選帳號。"
    }
    expand.isHidden = !focused || unpinned.isEmpty
    expand.title = focusExpanded ? "收起全部帳號" : "展開全部帳號（\(accounts.count)）"
    empty.isHidden = !visible.isEmpty
    empty.stringValue = accounts.isEmpty ? emptyMessage : "尚未釘選帳號。請展開全部查看用量，或到設定新增 pin。"
    accountsStack.isHidden = visible.isEmpty
    let ids = visible.map(\.id)
    if ids != visibleIDs {
      for card in accountsStack.arrangedSubviews {
        accountsStack.removeArrangedSubview(card)
        card.removeFromSuperview()
      }
      for account in visible {
        let card = accountViews[account.id] ?? UsageAccountView()
        accountViews[account.id] = card
        UsageStyle.add(card, to: accountsStack)
      }
      visibleIDs = ids
    }
    let accountIDs = Set(accounts.map(\.id))
    accountViews = accountViews.filter { accountIDs.contains($0.key) }
    for account in visible {
      accountViews[account.id]?.update(account, dense: dense, table: layout == "table")
    }
    view.layoutSubtreeIfNeeded()
    var y = oldY
    if let anchor = anchor, ids.contains(anchor), let card = accountViews[anchor],
       let offset = anchorOffset {
      y = card.convert(card.bounds, to: document).minY + offset
    }
    let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, y))))
    scroll.reflectScrolledClipView(scroll.contentView)
  }

  @objc private func toggleFocus() {
    focusExpanded.toggle()
    renderAccounts()
  }

  @objc private func refreshUsage() { onRefresh?() }
  @objc private func openSettings() { onSettings?() }
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

  func hasSameArtwork(as other: StatusPin) -> Bool {
    provider == other.provider && showIcon == other.showIcon &&
      label == other.label && labelWidth == other.labelWidth &&
      color == other.color && status == other.status && layers == other.layers
  }
}

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  private var engine: FlutterEngine?
  private var desktopChannel: FlutterMethodChannel?
  private var panel: UsagePanel?
  private var usageController: UsagePanelController?
  private var settingsWindow: NSWindow?
  private var statusItem: NSStatusItem?
  private var pinArtwork: [String: (pin: StatusPin, image: NSImage)] = [:]
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
    createStatusItem()

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
    controller.backgroundColor = .clear
    let settingsGlass = GlassSurface(cornerRadius: 0)
    controller.view.addSubview(settingsGlass, positioned: .below, relativeTo: nil)
    settingsGlass.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      settingsGlass.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
      settingsGlass.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
      settingsGlass.topAnchor.constraint(equalTo: controller.view.topAnchor),
      settingsGlass.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
    ])
    RegisterGeneratedPlugins(registry: controller)
    let settings = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    settings.title = "AnyUsagePin 設定"
    settings.backgroundColor = .windowBackgroundColor
    settings.isOpaque = false
    settings.titlebarAppearsTransparent = false
    settings.toolbarStyle = .unified
    settings.isReleasedWhenClosed = false
    settings.hidesOnDeactivate = false
    settings.level = .normal
    settings.minSize = NSSize(width: 620, height: 480)
    settings.delegate = self
    settings.contentViewController = controller
    settings.setContentSize(NSSize(width: 720, height: 760))
    settings.center()
    settingsWindow = settings
    mainFlutterWindow = settings

    let usageController = UsagePanelController()
    usageController.onRefresh = { [weak self] in
      self?.desktopChannel?.invokeMethod("desktop.refresh", arguments: nil)
    }
    usageController.onSettings = { [weak self] in self?.showSettings() }
    self.usageController = usageController
    let panel = UsagePanel(
      contentRect: NSRect(x: 0, y: 0, width: 380, height: 620),
      styleMask: [.borderless],
      backing: .buffered, defer: false)
    panel.title = "AnyUsagePin 用量"
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = false
    panel.hidesOnDeactivate = false
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.delegate = self
    panel.contentViewController = usageController
    panel.setContentSize(NSSize(width: 380, height: 620))
    self.panel = panel
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
    case "panel.update":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: "Expected panel data.", details: nil))
        return
      }
      let appearance: NSAppearance?
      switch arguments["theme"] as? String {
      case "light": appearance = NSAppearance(named: .aqua)
      case "dark": appearance = NSAppearance(named: .darkAqua)
      default: appearance = nil
      }
      settingsWindow?.appearance = appearance
      panel?.appearance = appearance
      usageController?.update(arguments)
      result(nil)
    case "app.launchAtLoginStatus":
      do {
        result(try launchAtLoginStatus())
      } catch {
        result(FlutterError(code: "login_item", message: error.localizedDescription, details: nil))
      }
    case "app.setLaunchAtLogin":
      guard let arguments = call.arguments as? [String: Any],
            let enabled = arguments["enabled"] as? Bool else {
        result(FlutterError(code: "invalid_arguments", message: "Expected an enabled flag.", details: nil))
        return
      }
      do {
        try setLaunchAtLogin(enabled)
        result(try launchAtLoginStatus())
      } catch {
        result(FlutterError(code: "login_item", message: error.localizedDescription, details: nil))
      }
    case "app.openLoginItemSettings":
      if #available(macOS 13.0, *) {
        SMAppService.openSystemSettingsLoginItems()
      }
      result(nil)
    case "app.quit":
      result(nil)
      NSApp.terminate(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var legacyLoginItemURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
      .appendingPathComponent("\(Bundle.main.bundleIdentifier!).plist")
  }

  private func launchAtLoginStatus() throws -> String {
    if #available(macOS 13.0, *) {
      switch SMAppService.mainApp.status {
      case .enabled: return "enabled"
      case .requiresApproval: return "requiresApproval"
      case .notRegistered, .notFound: break
      @unknown default:
        throw NSError(domain: "AnyUsagePin.LoginItem", code: 2, userInfo: [
          NSLocalizedDescriptionKey: "無法辨識系統登入項目狀態。",
        ])
      }
    }
    return FileManager.default.fileExists(atPath: legacyLoginItemURL.path)
      ? "enabled" : "disabled"
  }

  private func setLaunchAtLogin(_ enabled: Bool) throws {
    let fileManager = FileManager.default
    let legacyURL = legacyLoginItemURL
    if #available(macOS 13.0, *) {
      let service = SMAppService.mainApp
      if enabled {
        if service.status != .enabled && service.status != .requiresApproval {
          try service.register()
        }
      } else if service.status == .enabled || service.status == .requiresApproval {
        try service.unregister()
      }
      // Remove the macOS 12 registration when changing the setting after an OS upgrade.
      if fileManager.fileExists(atPath: legacyURL.path) {
        try fileManager.removeItem(at: legacyURL)
      }
    } else if enabled {
      // macOS 12 predates SMAppService. This user agent opens the app once at login.
      let plist: [String: Any] = [
        "Label": Bundle.main.bundleIdentifier!,
        "ProgramArguments": ["/usr/bin/open", "-g", Bundle.main.bundlePath],
        "RunAtLoad": true,
        "LaunchOnlyOnce": true,
      ]
      let data = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0)
      try fileManager.createDirectory(
        at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: legacyURL, options: .atomic)
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyURL.path)
    } else if fileManager.fileExists(atPath: legacyURL.path) {
      try fileManager.removeItem(at: legacyURL)
    }
  }

  private func createStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem = item
    item.isVisible = true
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
    guard pins != newPins else { return }
    let orderChanged = !pins.elementsEqual(newPins, by: { $0.id == $1.id })
    if orderChanged {
      let ids = Set(newPins.map(\.id))
      for pin in pins where !ids.contains(pin.id) {
        pinArtwork.removeValue(forKey: pin.id)
      }
    }
    pins = newPins
    renderPins(redraw: orderChanged)
  }

  private func redrawPins() {
    pinArtwork.removeAll(keepingCapacity: true)
    renderPins(redraw: true)
  }

  private func renderPins(redraw: Bool) {
    guard let item = statusItem, let button = item.button else { return }
    if pins.isEmpty {
      item.length = NSStatusItem.squareLength
      button.image = StatusArtwork.launcherImage
      button.toolTip = "AnyUsagePin"
      button.setAccessibilityLabel("Open AnyUsagePin")
      button.setAccessibilityValue(nil)
      return
    }
    button.effectiveAppearance.performAsCurrentDrawingAppearance {
      var needsRedraw = redraw || button.image == nil
      for pin in pins {
        if let cached = pinArtwork[pin.id], pin.hasSameArtwork(as: cached.pin) { continue }
        pinArtwork[pin.id] = (pin, StatusArtwork.image(for: pin))
        needsRedraw = true
      }
      if needsRedraw {
        let automaticColor: NSColor = button.effectiveAppearance.bestMatch(
          from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
        let image = StatusArtwork.image(
          for: pins, artwork: pinArtwork, automaticColor: automaticColor)
        item.length = image.size.width
        button.image = image
        button.imagePosition = .imageOnly
      }
    }
    let tooltip = pins.map(\.tooltip).joined(separator: "\n\n")
    button.toolTip = tooltip
    button.setAccessibilityLabel(pins.map(\.title).joined(separator: ", "))
    button.setAccessibilityValue(tooltip)
  }

  @objc private func statusClicked(_ sender: NSStatusBarButton) {
    anchorButton = sender
    if NSApp.currentEvent?.type == .rightMouseUp ||
        NSApp.currentEvent?.modifierFlags.contains(.control) == true {
      let menu = NSMenu()
      let open = NSMenuItem(title: "Open", action: #selector(openFromMenu), keyEquivalent: "")
      open.target = self
      menu.addItem(open)
      let settings = NSMenuItem(
        title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
      settings.target = self
      menu.addItem(settings)
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
  @objc private func openSettingsFromMenu() { showSettings() }

  private func showSettings() {
    hidePanel()
    guard let settings = settingsWindow else { return }
    NSApp.activate(ignoringOtherApps: true)
    if settings.isMiniaturized { settings.deminiaturize(nil) }
    settings.makeKeyAndOrderFront(nil)
    if let inputView = settings.contentViewController?.view.subviews.first(where: { $0.acceptsFirstResponder }) {
      settings.makeFirstResponder(inputView)
    }
  }
  @objc private func quitFromMenu() { NSApp.terminate(nil) }

  private func showPanel() {
    requestedOpen = true
    guard ready, let panel = panel else { return }
    let wasVisible = panel.isVisible
    if !wasVisible { positionPanel(panel) }
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    if !wasVisible { desktopChannel?.invokeMethod("desktop.opened", arguments: nil) }
  }

  private func positionPanel(_ panel: NSPanel) {
    let button = anchorButton ?? statusItem?.button
    let screen = button?.window?.screen ?? NSScreen.main
    guard let screen = screen else { panel.center(); return }
    let visible = screen.visibleFrame
    var frame = panel.frame
    frame.size.width = min(380, visible.width)
    frame.size.height = min(620, visible.height - 12)
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
    if sender === panel {
      hidePanel()
    } else if sender === settingsWindow {
      sender.orderOut(nil)
    } else {
      return true
    }
    return false
  }

  func windowDidBecomeKey(_ notification: Notification) {
    guard ready, let window = notification.object as? NSWindow,
          window === settingsWindow else { return }
    desktopChannel?.invokeMethod("desktop.settingsOpened", arguments: nil)
  }

  func windowDidResignKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === panel else { return }
    hidePanel()
  }

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
          if event.keyCode == 53 && event.window === panel {
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

  static func logo(for provider: String) -> NSImage? {
    if let image = logos[provider] { return image }
    switch provider {
    case "anthropic", "openai-codex", "google-antigravity", "xai-oauth", "cursor": break
    default:
      return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
    }
    let key = FlutterDartProject.lookupKey(forAsset: "assets/providers/\(provider).png")
    let url = Bundle.main.bundleURL.appendingPathComponent(key)
    guard let image = NSImage(contentsOf: url) else { return nil }
    image.isTemplate = provider != "anthropic" && provider != "google-antigravity"
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

  static func image(
    for pins: [StatusPin], artwork: [String: (pin: StatusPin, image: NSImage)],
    automaticColor: NSColor
  ) -> NSImage {
    let gap: CGFloat = 4
    var width: CGFloat = 0
    var isTemplate = true
    for pin in pins {
      guard let image = artwork[pin.id]?.image else { continue }
      width += image.size.width
      isTemplate = isTemplate && image.isTemplate
    }
    width += CGFloat(max(0, pins.count - 1)) * gap
    let image = NSImage(size: NSSize(width: width, height: 22))
    image.lockFocus()
    var x: CGFloat = 0
    for pin in pins {
      guard let pinImage = artwork[pin.id]?.image else { continue }
      let rect = NSRect(x: x, y: 0, width: pinImage.size.width, height: 22)
      pinImage.draw(in: rect)
      if !isTemplate && pinImage.isTemplate {
        // Mixed custom colors cannot use a single template tint.
        automaticColor.setFill()
        rect.fill(using: .sourceAtop)
      }
      x += pinImage.size.width + gap
    }
    image.unlockFocus()
    image.isTemplate = isTemplate
    return image
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
