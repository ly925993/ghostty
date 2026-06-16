import Combine
import Foundation

@MainActor
final class SSHConnectionsViewModel: ObservableObject {
    struct Section: Equatable, Identifiable {
        let id: String
        let group: SSHConnectionGroup?
        let connections: [SSHConnection]

        var title: String {
            group?.name ?? "未分组"
        }
    }

    struct ConnectionDraft: Equatable, Identifiable {
        let id = UUID()
        var connectionID: UUID?
        var groupID: UUID?
        var name: String
        var host: String
        var port: String
        var username: String
        var privateKeyPath: String
        var notes: String

        init(
            connectionID: UUID? = nil,
            groupID: UUID? = nil,
            name: String = "",
            host: String = "",
            port: String = "22",
            username: String = "",
            privateKeyPath: String = "",
            notes: String = ""
        ) {
            self.connectionID = connectionID
            self.groupID = groupID
            self.name = name
            self.host = host
            self.port = port
            self.username = username
            self.privateKeyPath = privateKeyPath
            self.notes = notes
        }

        init(connection: SSHConnection) {
            self.init(
                connectionID: connection.id,
                groupID: connection.groupID,
                name: connection.name,
                host: connection.host,
                port: String(connection.port),
                username: connection.username,
                privateKeyPath: connection.privateKeyPath,
                notes: connection.notes
            )
        }
    }

    struct GroupDraft: Equatable, Identifiable {
        let id = UUID()
        var groupID: UUID?
        var name: String

        init(groupID: UUID? = nil, name: String = "") {
            self.groupID = groupID
            self.name = name
        }

        init(group: SSHConnectionGroup) {
            self.init(groupID: group.id, name: group.name)
        }
    }

    enum ConnectionField: String, Hashable {
        case name
        case host
        case port
    }

    enum ContentState: Equatable {
        case emptyLibrary
        case noResults
        case content
    }

    @Published var searchText = ""
    @Published private(set) var library: SSHConnectionLibrary
    @Published private(set) var connectionValidationErrors: [ConnectionField: String] = [:]
    @Published private(set) var groupValidationError: String?
    @Published var alertMessage: String?

    private let store: SSHConnectionStore
    private let reachabilityChecker: SSHReachabilityChecker
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: SSHConnectionStore? = nil,
        reachabilityChecker: SSHReachabilityChecker? = nil
    ) {
        let store = store ?? .shared
        let reachabilityChecker = reachabilityChecker ?? SSHReachabilityChecker()

        self.store = store
        self.reachabilityChecker = reachabilityChecker
        self.library = store.library

        store.$library
            .sink { [weak self] library in
                Task { @MainActor in
                    self?.library = library
                }
            }
            .store(in: &cancellables)

        reachabilityChecker.$statuses
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var contentState: ContentState {
        if library.connections.isEmpty && library.groups.isEmpty {
            return .emptyLibrary
        }

        if !normalizedSearchText.isEmpty && visibleConnections.isEmpty {
            return .noResults
        }

        return .content
    }

    var visibleConnections: [SSHConnection] {
        let query = normalizedSearchText.lowercased()
        guard !query.isEmpty else { return library.connections }

        return library.connections.filter { connection in
            [
                connection.name,
                connection.host,
                connection.username,
                connection.notes,
            ].contains { value in
                value.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var sections: [Section] {
        let queryIsEmpty = normalizedSearchText.isEmpty
        let groupIDs = Set(library.groups.map(\.id))
        var result: [Section] = []

        for group in library.groups {
            let connections = visibleConnections.filter { $0.groupID == group.id }
            if queryIsEmpty || !connections.isEmpty {
                result.append(Section(
                    id: group.id.uuidString,
                    group: group,
                    connections: connections
                ))
            }
        }

        let ungrouped = visibleConnections.filter { connection in
            guard let groupID = connection.groupID else { return true }
            return !groupIDs.contains(groupID)
        }
        if !ungrouped.isEmpty {
            result.append(Section(id: "ungrouped", group: nil, connections: ungrouped))
        }

        return result
    }

    func status(for connection: SSHConnection) -> SSHConnectionStatus {
        reachabilityChecker.status(for: connection.id)
    }

    func refresh(_ connection: SSHConnection) {
        reachabilityChecker.refresh(connection)
    }

    func refresh(_ section: Section) {
        reachabilityChecker.refresh(section.connections)
    }

    func refreshVisibleConnections() {
        reachabilityChecker.refresh(visibleConnections)
    }

    func connectionDraft(for groupID: UUID? = nil) -> ConnectionDraft {
        connectionValidationErrors = [:]
        return ConnectionDraft(groupID: groupID)
    }

    func connectionDraft(for connection: SSHConnection) -> ConnectionDraft {
        connectionValidationErrors = [:]
        return ConnectionDraft(connection: connection)
    }

    func groupDraft() -> GroupDraft {
        groupValidationError = nil
        return GroupDraft()
    }

    func groupDraft(for group: SSHConnectionGroup) -> GroupDraft {
        groupValidationError = nil
        return GroupDraft(group: group)
    }

    @discardableResult
    func saveConnection(_ draft: ConnectionDraft) -> Bool {
        connectionValidationErrors = validateConnection(draft)
        guard connectionValidationErrors.isEmpty else { return false }
        guard let connection = makeConnection(from: draft) else { return false }

        let saved = store.update { library in
            if let index = library.connections.firstIndex(where: { $0.id == connection.id }) {
                library.connections[index] = connection
            } else {
                library.connections.append(connection)
            }
        }
        alertMessage = saved ? nil : store.saveError?.localizedDescription
        return saved
    }

    @discardableResult
    func saveGroup(_ draft: GroupDraft) -> Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            groupValidationError = "请输入分组名称。"
            return false
        }

        groupValidationError = nil
        let group = SSHConnectionGroup(id: draft.groupID ?? UUID(), name: name)
        let saved = store.update { library in
            if let index = library.groups.firstIndex(where: { $0.id == group.id }) {
                library.groups[index] = group
            } else {
                library.groups.append(group)
            }
        }
        alertMessage = saved ? nil : store.saveError?.localizedDescription
        return saved
    }

    @discardableResult
    func deleteConnection(_ connection: SSHConnection) -> Bool {
        let saved = store.update { library in
            library.connections.removeAll { $0.id == connection.id }
        }
        alertMessage = saved ? nil : store.saveError?.localizedDescription
        return saved
    }

    @discardableResult
    func deleteGroup(_ group: SSHConnectionGroup) -> Bool {
        guard !library.connections.contains(where: { $0.groupID == group.id }) else {
            alertMessage = "请先移动或删除此分组中的连接。"
            return false
        }

        let saved = store.update { library in
            library.groups.removeAll { $0.id == group.id }
        }
        alertMessage = saved ? nil : store.saveError?.localizedDescription
        return saved
    }

    func presentError(_ error: Error) {
        alertMessage = error.localizedDescription
    }

    func validateConnection(_ draft: ConnectionDraft) -> [ConnectionField: String] {
        var errors: [ConnectionField: String] = [:]
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.name] = "请输入名称。"
        }
        if draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.host] = "请输入主机地址。"
        }
        if portValue(from: draft.port) == nil {
            errors[.port] = "端口必须在 1 到 65535 之间。"
        }
        return errors
    }

    private func makeConnection(from draft: ConnectionDraft) -> SSHConnection? {
        guard let port = portValue(from: draft.port) else { return nil }
        return SSHConnection(
            id: draft.connectionID ?? UUID(),
            groupID: draft.groupID,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: draft.host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            username: draft.username.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPath: draft.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func portValue(from text: String) -> UInt16? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(value)
        else {
            return nil
        }

        return UInt16(value)
    }
}
