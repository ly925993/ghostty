import Foundation

@MainActor
final class SSHConnectionStore: ObservableObject {
    enum StoreError: Error, Equatable, LocalizedError {
        case loadFailed
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .loadFailed:
                "无法加载 SSH 连接。"
            case .saveFailed:
                "无法保存 SSH 连接。"
            }
        }
    }

    @Published private(set) var library: SSHConnectionLibrary
    @Published private(set) var loadError: StoreError?
    @Published private(set) var saveError: StoreError?

    let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    static let shared = SSHConnectionStore()

    init(
        fileURL: URL = SSHConnectionStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.library = SSHConnectionLibrary()

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    nonisolated static func defaultFileURL(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        fileManager: FileManager = .default
    ) -> URL {
        let appIdentifier = bundleIdentifier ?? "com.mitchellh.ghostty"
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        return base
            .appendingPathComponent(appIdentifier, isDirectory: true)
            .appendingPathComponent("ssh-connections.json", isDirectory: false)
    }

    func load() {
        loadError = nil
        saveError = nil

        guard fileManager.fileExists(atPath: fileURL.path) else {
            library = SSHConnectionLibrary()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            library = try decoder.decode(SSHConnectionLibrary.self, from: data)
        } catch {
            library = SSHConnectionLibrary()
            loadError = .loadFailed
        }
    }

    @discardableResult
    func save(_ nextLibrary: SSHConnectionLibrary) -> Bool {
        saveError = nil

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try encoder.encode(nextLibrary)
            try data.write(to: fileURL, options: [.atomic])
            setOwnerOnlyPermissionsIfPossible()
            library = nextLibrary
            return true
        } catch {
            saveError = .saveFailed
            return false
        }
    }

    @discardableResult
    func update(_ transform: (inout SSHConnectionLibrary) -> Void) -> Bool {
        var next = library
        transform(&next)
        return save(next)
    }

    private func setOwnerOnlyPermissionsIfPossible() {
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
