import Foundation

struct SSHConnectionLibrary: Codable, Equatable, Sendable {
    var groups: [SSHConnectionGroup]
    var connections: [SSHConnection]

    init(
        groups: [SSHConnectionGroup] = [],
        connections: [SSHConnection] = []
    ) {
        self.groups = groups
        self.connections = connections
    }

    var isEmpty: Bool {
        groups.isEmpty && connections.isEmpty
    }
}
