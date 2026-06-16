import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SSHConnectionStoreTests {
    @Test func missingFileLoadsEmptyLibrary() {
        let url = temporaryDirectory().appendingPathComponent("ssh-connections.json")

        let store = SSHConnectionStore(fileURL: url)

        #expect(store.library == SSHConnectionLibrary())
        #expect(store.loadError == nil)
    }

    @Test func savesAndReloadsLibraryPreservingIDsFieldsAndOrdering() throws {
        let url = temporaryDirectory().appendingPathComponent("ssh-connections.json")
        let groupOne = SSHConnectionGroup(id: UUID(), name: "Production")
        let groupTwo = SSHConnectionGroup(id: UUID(), name: "Staging")
        let connectionOne = SSHConnection(
            id: UUID(),
            groupID: groupOne.id,
            name: "API",
            host: "api.example.com",
            port: 2222,
            username: "deploy",
            privateKeyPath: "/Users/me/.ssh/prod key",
            notes: "Primary API"
        )
        let connectionTwo = SSHConnection(
            id: UUID(),
            groupID: groupTwo.id,
            name: "Worker",
            host: "worker.example.com",
            port: 22,
            username: "ops",
            notes: "Background jobs"
        )
        let library = SSHConnectionLibrary(
            groups: [groupOne, groupTwo],
            connections: [connectionOne, connectionTwo]
        )

        let store = SSHConnectionStore(fileURL: url)
        #expect(store.save(library))

        let reloaded = SSHConnectionStore(fileURL: url)
        #expect(reloaded.library == library)
        #expect(reloaded.library.groups.map(\.id) == [groupOne.id, groupTwo.id])
        #expect(reloaded.library.connections.map(\.id) == [connectionOne.id, connectionTwo.id])
    }

    @Test func connectionWithoutPrivateKeyDoesNotSynthesizeSecretField() throws {
        let connection = SSHConnection(name: "No Key", host: "example.com")
        let library = SSHConnectionLibrary(connections: [connection])

        let data = try JSONEncoder().encode(library)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("privateKeyPath"))
        #expect(!json.contains("password"))
        #expect(!json.contains("passphrase"))
        #expect(!json.contains("privateKeyContent"))
    }

    @Test func malformedJSONReportsGenericLoadError() throws {
        let url = temporaryDirectory().appendingPathComponent("ssh-connections.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {"host":"sensitive.example.com","username":"secret-user","privateKeyPath":"/Users/me/.ssh/private"}
        """.write(to: url, atomically: true, encoding: .utf8)

        let store = SSHConnectionStore(fileURL: url)
        let message = try #require(store.loadError?.localizedDescription)

        #expect(store.library == SSHConnectionLibrary())
        #expect(message == "无法加载 SSH 连接。")
        #expect(!message.contains("sensitive.example.com"))
        #expect(!message.contains("secret-user"))
        #expect(!message.contains("/Users/me/.ssh/private"))
    }

    @Test func saveFailureReportsGenericErrorAndKeepsCurrentLibrary() throws {
        let directory = temporaryDirectory()
        let existing = SSHConnectionLibrary(connections: [
            SSHConnection(name: "Existing", host: "existing.example.com"),
        ])
        let store = SSHConnectionStore(fileURL: directory.appendingPathComponent("ssh-connections.json"))
        #expect(store.save(existing))

        let blockedURL = directory.appendingPathComponent("not-a-directory").appendingPathComponent("ssh-connections.json")
        try "file".write(to: blockedURL.deletingLastPathComponent(), atomically: true, encoding: .utf8)
        let blockedStore = SSHConnectionStore(fileURL: blockedURL)
        let next = SSHConnectionLibrary(connections: [
            SSHConnection(name: "Sensitive", host: "sensitive.example.com", username: "secret-user"),
        ])

        #expect(!blockedStore.save(next))
        let message = try #require(blockedStore.saveError?.localizedDescription)
        #expect(message == "无法保存 SSH 连接。")
        #expect(!message.contains("sensitive.example.com"))
        #expect(!message.contains("secret-user"))
        #expect(blockedStore.library == SSHConnectionLibrary())
    }

    @Test func defaultStoragePathUsesBundleIdentifier() {
        let url = SSHConnectionStore.defaultFileURL(bundleIdentifier: "com.example.GhosttyDebug")

        #expect(url.path.contains("Application Support/com.example.GhosttyDebug/ssh-connections.json"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-ssh-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
