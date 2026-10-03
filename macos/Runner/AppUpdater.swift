import Cocoa
import Sparkle

enum AppUpdateStatus {
  case idle
  case checking
  case available(String)
  case noUpdate
  case failed
  case disabled
}

@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
  var onChange: (() -> Void)?
  private(set) var status: AppUpdateStatus = .idle {
    didSet { onChange?() }
  }
  private var started = false
  private var availabilityObservation: NSKeyValueObservation?
  private lazy var controller = SPUStandardUpdaterController(
    startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)

  var canCheckForUpdates: Bool {
    started && controller.updater.canCheckForUpdates
  }

  func start() {
    availabilityObservation = controller.updater.observe(
      \.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
        DispatchQueue.main.async { self?.onChange?() }
      }
    do {
      try controller.updater.start()
      started = true
      checkWhenOpened()
    } catch {
      status = .failed
    }
  }

  func checkWhenOpened() {
    guard started else { return }
    let updater = controller.updater
    guard updater.automaticallyChecksForUpdates else {
      status = .disabled
      return
    }
    // A scheduled alert or another panel-opening probe already owns this session.
    guard !updater.sessionInProgress else { return }
    status = .checking
    updater.checkForUpdateInformation()
  }

  func showUpdate() {
    guard canCheckForUpdates else { return }
    controller.checkForUpdates(nil)
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    status = .available(item.displayVersionString)
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
    // An OS-incompatible or skipped update is not evidence that this is the latest version.
    status = .noUpdate
  }

  func updater(
    _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
    error: Error?
  ) {
    if let error = error as NSError?,
       error.domain != SUSparkleErrorDomain || error.code != SUError.noUpdateError.rawValue {
      status = .failed
    }
    onChange?()
  }

  func updater(
    _ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
    forUpdate update: SUAppcastItem, state: SPUUserUpdateState
  ) {
    if choice == .skip { status = .noUpdate }
  }

  var supportsGentleScheduledUpdateReminders: Bool { true }

  func standardUserDriverShouldHandleShowingScheduledUpdate(
    _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
  ) -> Bool {
    false
  }

  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
    state: SPUUserUpdateState
  ) {
    status = .available(update.displayVersionString)
  }
}
