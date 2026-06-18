import Foundation

enum DaemonLifecycle {
  private static let terminationLock = NSLock()
  private static var terminationHandlers: [() -> Void] = []

  static func registerTerminationHandler(_ handler: @escaping () -> Void) {
    terminationLock.lock()
    terminationHandlers.append(handler)
    terminationLock.unlock()
  }

  static func waitForTermination() {
    let semaphore = DispatchSemaphore(value: 0)

    registerTerminationHandler {
      semaphore.signal()
    }

    installSignalHandlers()
    semaphore.wait()
  }

  private static func installSignalHandlers() {
    signal(SIGTERM, Self.handleSignal)
    signal(SIGINT, Self.handleSignal)
  }

  private static let handleSignal: @convention(c) (Int32) -> Void = { _ in
    terminationLock.lock()
    let handlers = terminationHandlers
    terminationLock.unlock()

    for handler in handlers {
      handler()
    }
  }
}
