import Foundation
import UserNotifications
import MiniOpsKit

@MainActor
final class NotificationMonitor {
    static let shared = NotificationMonitor()

    private let preferences = ClientPreferences.shared
    private var lastOverall: OverallStatus?
    private var lastConnectionError: String?
    private var notifiedStoppedContainers: Set<String> = []
    private var notifiedUnhealthyChecks: Set<String> = []
    private var lastNotifiedLogAlertDate: Date = .distantPast
    private var wasCpuHigh = false
    private var wasMemoryHigh = false
    private var wasDiskHigh = false

    private init() {}

    func requestAuthorizationIfNeeded() {
        guard preferences.notificationsEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(monitoringService: MonitoringService) {
        guard preferences.notificationsEnabled else { return }

        let snapshot = monitoringService.snapshot

        if let error = monitoringService.connectionError {
            if error != lastConnectionError {
                post(title: "MiniOps 연결 끊김", body: error)
            }
            lastConnectionError = error
            return
        }
        lastConnectionError = nil

        if let previous = lastOverall, previous != snapshot.overall {
            switch snapshot.overall {
            case .critical where preferences.notifyOnCritical:
                post(title: "MiniOps — 장애", body: "\(monitoringService.displaySourceName) 상태가 장애입니다.")
            case .warning where preferences.notifyOnWarning:
                post(title: "MiniOps — 경고", body: "\(monitoringService.displaySourceName) 상태가 경고입니다.")
            default:
                break
            }
        }
        lastOverall = snapshot.overall

        let metrics = snapshot.metrics

        let cpuHigh = metrics.cpuUsagePercent >= preferences.cpuThreshold
        if cpuHigh && !wasCpuHigh {
            post(title: "CPU 사용률 높음", body: String(format: "CPU %.0f%% (임계치 %.0f%%)", metrics.cpuUsagePercent, preferences.cpuThreshold))
        }
        wasCpuHigh = cpuHigh

        let memoryHigh = metrics.memoryUsagePercent >= preferences.memoryThreshold
        if memoryHigh && !wasMemoryHigh {
            post(title: "메모리 사용률 높음", body: String(format: "Memory %.0f%% (임계치 %.0f%%)", metrics.memoryUsagePercent, preferences.memoryThreshold))
        }
        wasMemoryHigh = memoryHigh

        let diskHigh = metrics.diskUsagePercent >= preferences.diskThreshold
        if diskHigh && !wasDiskHigh {
            post(title: "디스크 사용률 높음", body: String(format: "Disk %.0f%% (임계치 %.0f%%)", metrics.diskUsagePercent, preferences.diskThreshold))
        }
        wasDiskHigh = diskHigh

        let stopped = Set(snapshot.docker.containers.filter { !$0.isRunning }.map(\.name))
        let newlyStopped = stopped.subtracting(notifiedStoppedContainers)
        for name in newlyStopped {
            post(title: "Docker 컨테이너 중지", body: "\(name) 컨테이너가 중지되었습니다.")
        }
        notifiedStoppedContainers = stopped

        let unhealthy = Set(snapshot.healthChecks.filter { !$0.isHealthy }.map(\.name))
        let newlyUnhealthy = unhealthy.subtracting(notifiedUnhealthyChecks)
        for name in newlyUnhealthy {
            post(title: "Health Check 실패", body: "\(name) 응답에 실패했습니다.")
        }
        notifiedUnhealthyChecks = unhealthy

        if preferences.notifyOnLogErrors {
            let newAlerts = snapshot.logAlerts.filter { $0.detectedAt > lastNotifiedLogAlertDate }
            if !newAlerts.isEmpty {
                let errorCount = newAlerts.filter { $0.level == .error }.count
                let warnCount  = newAlerts.filter { $0.level == .warn  }.count
                var parts: [String] = []
                if errorCount > 0 { parts.append("에러 \(errorCount)건") }
                if warnCount  > 0 { parts.append("경고 \(warnCount)건") }
                post(title: "Docker 로그 이상 감지", body: parts.joined(separator: ", "))
                lastNotifiedLogAlertDate = newAlerts.map(\.detectedAt).max() ?? Date()
            }
        }
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
