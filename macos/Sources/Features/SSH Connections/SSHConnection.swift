import Foundation

struct SSHConnection: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var groupID: UUID?
    var name: String
    var host: String
    var port: UInt16
    var username: String
    var privateKeyPath: String
    var notes: String

    init(
        id: UUID = UUID(),
        groupID: UUID? = nil,
        name: String,
        host: String,
        port: UInt16 = 22,
        username: String = "",
        privateKeyPath: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.groupID = groupID
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.privateKeyPath = privateKeyPath
        self.notes = notes
    }
}
