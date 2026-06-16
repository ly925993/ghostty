import Foundation

struct SSHConnectionGroup: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
