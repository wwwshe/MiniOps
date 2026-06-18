import Foundation
import MiniOpsKit

@MainActor
enum AppContainer {
    static var monitoringService: MonitoringService?
    static var httpServer: HTTPServer?
}
