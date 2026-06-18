import Foundation

struct DockerLogRequest: Identifiable, Hashable, Codable {
    let containerName: String

    var id: String { containerName }
}
