import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SSHConnectionsViewModelTests {
    @Test func sectionsPreserveSavedGroupAndConnectionOrder() {
        let production = SSHConnectionGroup(name: "Production")
        let staging = SSHConnectionGroup(name: "Staging")
        let api = SSHConnection(groupID: production.id, name: "API", host: "api.example.com")
        let db = SSHConnection(groupID: production.id, name: "DB", host: "db.example.com")
        let canary = SSHConnection(groupID: staging.id, name: "Canary", host: "canary.example.com")
        let viewModel = makeViewModel(library: SSHConnectionLibrary(
            groups: [production, staging],
            connections: [api, db, canary]
        ))

        #expect(viewModel.sections.map(\.title) == ["Production", "Staging"])
        #expect(viewModel.sections[0].connections.map(\.id) == [api.id, db.id])
        #expect(viewModel.sections[1].connections.map(\.id) == [canary.id])
    }

    @Test func searchMatchesNameHostUsernameAndNotes() {
        let group = SSHConnectionGroup(name: "Production")
        let byName = SSHConnection(groupID: group.id, name: "API", host: "one.example.com")
        let byHost = SSHConnection(groupID: group.id, name: "Other", host: "jump.example.com")
        let byUsername = SSHConnection(groupID: group.id, name: "User", host: "two.example.com", username: "deploy")
        let byNotes = SSHConnection(groupID: group.id, name: "Notes", host: "three.example.com", notes: "critical path")
        let viewModel = makeViewModel(library: SSHConnectionLibrary(
            groups: [group],
            connections: [byName, byHost, byUsername, byNotes]
        ))

        viewModel.searchText = "api"
        #expect(viewModel.visibleConnections.map(\.id) == [byName.id])

        viewModel.searchText = "jump"
        #expect(viewModel.visibleConnections.map(\.id) == [byHost.id])

        viewModel.searchText = "deploy"
        #expect(viewModel.visibleConnections.map(\.id) == [byUsername.id])

        viewModel.searchText = "critical"
        #expect(viewModel.visibleConnections.map(\.id) == [byNotes.id])
    }

    @Test func emptyAndNoResultsStatesDoNotMutateLibrary() {
        let empty = makeViewModel(library: SSHConnectionLibrary())
        #expect(empty.contentState == .emptyLibrary)

        let connection = SSHConnection(name: "API", host: "api.example.com")
        let viewModel = makeViewModel(library: SSHConnectionLibrary(connections: [connection]))
        viewModel.searchText = "missing"

        #expect(viewModel.contentState == .noResults)
        #expect(viewModel.library.connections == [connection])
    }

    @Test func invalidEditorInputReturnsFieldSpecificErrors() {
        let viewModel = makeViewModel()
        let draft = SSHConnectionsViewModel.ConnectionDraft(
            name: " ",
            host: "",
            port: "70000"
        )

        #expect(!viewModel.saveConnection(draft))
        #expect(viewModel.connectionValidationErrors[.name] == "Name is required.")
        #expect(viewModel.connectionValidationErrors[.host] == "Host is required.")
        #expect(viewModel.connectionValidationErrors[.port] == "Port must be between 1 and 65535.")
    }

    @Test func portValidationRejectsOutOfRangeValues() {
        let viewModel = makeViewModel()

        #expect(!viewModel.saveConnection(SSHConnectionsViewModel.ConnectionDraft(
            name: "API",
            host: "api.example.com",
            port: "0"
        )))
        #expect(viewModel.connectionValidationErrors[.port] == "Port must be between 1 and 65535.")

        #expect(!viewModel.saveConnection(SSHConnectionsViewModel.ConnectionDraft(
            name: "API",
            host: "api.example.com",
            port: "65536"
        )))
        #expect(viewModel.connectionValidationErrors[.port] == "Port must be between 1 and 65535.")
    }

    @Test func deletingNonEmptyGroupIsBlocked() {
        let group = SSHConnectionGroup(name: "Production")
        let connection = SSHConnection(groupID: group.id, name: "API", host: "api.example.com")
        let viewModel = makeViewModel(library: SSHConnectionLibrary(
            groups: [group],
            connections: [connection]
        ))

        #expect(!viewModel.deleteGroup(group))
        #expect(viewModel.alertMessage == "Move or delete connections in this group before deleting it.")
        #expect(viewModel.library.groups == [group])
    }

    @Test func saveFailureShowsGenericErrorWithoutConnectionMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-ssh-view-model-failure-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let blockedURL = directory
            .appendingPathComponent("not-a-directory")
            .appendingPathComponent("ssh-connections.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "file".write(to: blockedURL.deletingLastPathComponent(), atomically: true, encoding: .utf8)
        let store = SSHConnectionStore(fileURL: blockedURL)
        let viewModel = SSHConnectionsViewModel(store: store, reachabilityChecker: SSHReachabilityChecker(
            prober: FakeViewModelProber(results: [:])
        ))

        #expect(!viewModel.saveConnection(SSHConnectionsViewModel.ConnectionDraft(
            name: "Sensitive",
            host: "sensitive.example.com",
            username: "secret-user",
            privateKeyPath: "/Users/me/.ssh/private"
        )))

        let message = try #require(viewModel.alertMessage)
        #expect(message == "SSH connections could not be saved.")
        #expect(!message.contains("sensitive.example.com"))
        #expect(!message.contains("secret-user"))
        #expect(!message.contains("/Users/me/.ssh/private"))
    }

    @Test func statusUpdatesPropagateFromChecker() async throws {
        let connection = SSHConnection(name: "API", host: "api.example.com")
        let checker = SSHReachabilityChecker(prober: FakeViewModelProber(results: ["api.example.com:22": true]))
        let viewModel = makeViewModel(
            library: SSHConnectionLibrary(connections: [connection]),
            checker: checker
        )

        viewModel.refresh(connection)

        try await waitUntil {
            viewModel.status(for: connection) == .online
        }
    }

    private func makeViewModel(
        library: SSHConnectionLibrary = SSHConnectionLibrary(),
        checker: SSHReachabilityChecker = SSHReachabilityChecker(prober: FakeViewModelProber(results: [:]))
    ) -> SSHConnectionsViewModel {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-ssh-view-model-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("ssh-connections.json")
        let store = SSHConnectionStore(fileURL: url)
        _ = store.save(library)
        return SSHConnectionsViewModel(store: store, reachabilityChecker: checker)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        predicate: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for predicate")
    }
}

private actor FakeViewModelProber: SSHConnectionProbing {
    var results: [String: Bool]

    init(results: [String: Bool]) {
        self.results = results
    }

    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        results["\(host):\(port)"] ?? false
    }
}
