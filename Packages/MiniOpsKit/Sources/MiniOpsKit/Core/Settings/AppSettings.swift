import Foundation
import Observation

@Observable
public final class AppSettings {
    public static let shared = AppSettings()
    public static let configSuiteName = "com.miniops.settings"

    public static var configDirectoryPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Preferences/\(configSuiteName).plist"
    }

    private let defaults = UserDefaults(suiteName: configSuiteName) ?? .standard
    private let healthChecksKey = "healthCheckTargets"
    private let apiTokenKey = "apiToken"
    private let apiPortKey = "apiPort"
    private let dockerPathKey = "dockerPath"
    private let apiEnabledKey = "apiEnabled"
    private let monitoringModeKey = "monitoringMode"
    private let remoteServerBaseURLKey = "remoteServerBaseURL"
    private let remoteServerTokenKey = "remoteServerToken"
    private let remoteServerNameKey = "remoteServerName"

    public var healthCheckTargets: [HealthCheckTarget] {
        didSet { saveHealthChecks() }
    }

    public var apiToken: String {
        didSet { defaults.set(apiToken, forKey: apiTokenKey) }
    }

    public var apiPort: Int {
        didSet { defaults.set(apiPort, forKey: apiPortKey) }
    }

    public var dockerPath: String {
        didSet { defaults.set(dockerPath, forKey: dockerPathKey) }
    }

    public var apiEnabled: Bool {
        didSet { defaults.set(apiEnabled, forKey: apiEnabledKey) }
    }

    public var monitoringMode: MonitoringMode {
        didSet { defaults.set(monitoringMode.rawValue, forKey: monitoringModeKey) }
    }

    public var remoteServerBaseURL: String {
        didSet { defaults.set(remoteServerBaseURL, forKey: remoteServerBaseURLKey) }
    }

    public var remoteServerToken: String {
        didSet { defaults.set(remoteServerToken, forKey: remoteServerTokenKey) }
    }

    public var remoteServerName: String {
        didSet { defaults.set(remoteServerName, forKey: remoteServerNameKey) }
    }

    public var isClientMode: Bool { monitoringMode == .client }
    public var isAgentMode: Bool { monitoringMode == .agent }

    private init() {
        if let data = defaults.data(forKey: healthChecksKey),
           let decoded = try? JSONDecoder().decode([HealthCheckTarget].self, from: data) {
            healthCheckTargets = decoded
        } else {
            healthCheckTargets = []
        }

        let storedPort = defaults.integer(forKey: apiPortKey)
        apiPort = storedPort > 0 ? storedPort : 8787

        dockerPath = defaults.string(forKey: dockerPathKey) ?? "/usr/local/bin/docker"

        if defaults.object(forKey: apiEnabledKey) != nil {
            apiEnabled = defaults.bool(forKey: apiEnabledKey)
        } else {
            apiEnabled = true
        }

        if let token = defaults.string(forKey: apiTokenKey), !token.isEmpty {
            apiToken = token
        } else {
            let newToken = Self.generateToken()
            defaults.set(newToken, forKey: apiTokenKey)
            apiToken = newToken
        }

        if let modeRaw = defaults.string(forKey: monitoringModeKey),
           let mode = MonitoringMode(rawValue: modeRaw) {
            monitoringMode = mode
        } else {
            monitoringMode = .agent
        }

        remoteServerBaseURL = defaults.string(forKey: remoteServerBaseURLKey) ?? ""
        remoteServerToken = defaults.string(forKey: remoteServerTokenKey) ?? ""
        remoteServerName = defaults.string(forKey: remoteServerNameKey) ?? "Mac Mini Server"
    }

    public func regenerateAPIToken() {
        apiToken = Self.generateToken()
    }

    public func addHealthCheck(_ target: HealthCheckTarget) {
        healthCheckTargets.append(target)
    }

    public func updateHealthCheck(_ target: HealthCheckTarget) {
        guard let index = healthCheckTargets.firstIndex(where: { $0.id == target.id }) else { return }
        healthCheckTargets[index] = target
    }

    public func removeHealthCheck(id: UUID) {
        healthCheckTargets.removeAll { $0.id == id }
    }

    public func isSelfReferencingHealthCheck(_ urlString: String, apiPort: Int) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return false }

        let localHosts: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0", "::1"]
        guard localHosts.contains(host) else { return false }

        if let port = url.port {
            return port == apiPort
        }

        let path = url.path
        return path.hasPrefix("/api/")
    }

    private func saveHealthChecks() {
        guard let data = try? JSONEncoder().encode(healthCheckTargets) else { return }
        defaults.set(data, forKey: healthChecksKey)
    }

    private static func generateToken() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
