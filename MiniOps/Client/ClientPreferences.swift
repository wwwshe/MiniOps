import Foundation
import MiniOpsKit
import Observation

@Observable
final class ClientPreferences {
    static let shared = ClientPreferences()

    private let defaults = UserDefaults.standard

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    var notifyOnWarning: Bool {
        didSet { defaults.set(notifyOnWarning, forKey: Keys.notifyOnWarning) }
    }

    var notifyOnCritical: Bool {
        didSet { defaults.set(notifyOnCritical, forKey: Keys.notifyOnCritical) }
    }

    var cpuThreshold: Double {
        didSet { defaults.set(cpuThreshold, forKey: Keys.cpuThreshold) }
    }

    var memoryThreshold: Double {
        didSet { defaults.set(memoryThreshold, forKey: Keys.memoryThreshold) }
    }

    var diskThreshold: Double {
        didSet { defaults.set(diskThreshold, forKey: Keys.diskThreshold) }
    }

    private enum Keys {
        static let onboardingCompleted = "client.onboardingCompleted"
        static let notificationsEnabled = "client.notificationsEnabled"
        static let notifyOnWarning = "client.notifyOnWarning"
        static let notifyOnCritical = "client.notifyOnCritical"
        static let cpuThreshold = "client.cpuThreshold"
        static let memoryThreshold = "client.memoryThreshold"
        static let diskThreshold = "client.diskThreshold"
    }

    private init() {
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        notifyOnWarning = defaults.object(forKey: Keys.notifyOnWarning) as? Bool ?? true
        notifyOnCritical = defaults.object(forKey: Keys.notifyOnCritical) as? Bool ?? true
        cpuThreshold = defaults.object(forKey: Keys.cpuThreshold) as? Double ?? 85
        memoryThreshold = defaults.object(forKey: Keys.memoryThreshold) as? Double ?? 90
        diskThreshold = defaults.object(forKey: Keys.diskThreshold) as? Double ?? 95
    }
}

extension Notification.Name {
    static let openMiniOpsSettings = Notification.Name("openMiniOpsSettings")
}

extension APIHealthCheckTargetItem {
    var asHealthCheckTarget: HealthCheckTarget {
        HealthCheckTarget(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            urlString: url,
            intervalSeconds: intervalSeconds,
            timeoutSeconds: timeoutSeconds,
            expectedStatusCode: expectedStatusCode
        )
    }
}
