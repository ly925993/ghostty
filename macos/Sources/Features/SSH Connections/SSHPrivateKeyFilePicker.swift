import AppKit
import Foundation
import SwiftUI

enum SSHPrivateKeyFilePicker {
    struct KeyInfo: Equatable, Identifiable {
        var name: String
        var type: String
        var length: String
        var privateKeyURL: URL
        var publicKeyURL: URL?

        var id: String {
            privateKeyURL.path
        }
    }

    static var defaultDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
    }

    @MainActor
    static func configure(_ panel: NSOpenPanel) {
        panel.title = "选择用户密钥文件"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = defaultDirectoryURL
    }

    static func discoverKeys(in directory: URL = defaultDirectoryURL) -> [KeyInfo] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == "pub" }
            .compactMap { discoveredPublicKeyURL in
                let publicKeyURL = directory.appendingPathComponent(discoveredPublicKeyURL.lastPathComponent)
                let privateKeyURL = publicKeyURL.deletingPathExtension()
                guard fileManager.fileExists(atPath: privateKeyURL.path) else { return nil }
                return keyInfo(privateKeyURL: privateKeyURL, publicKeyURL: publicKeyURL)
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    @MainActor
    static func importKey() -> KeyInfo? {
        let panel = NSOpenPanel()
        configure(panel)
        panel.title = "导入用户密钥文件"
        panel.prompt = "导入"

        guard panel.runModal() == .OK else { return nil }
        guard let url = panel.url else { return nil }
        return keyInfo(selectedURL: url)
    }

    static func keyInfo(selectedURL: URL) -> KeyInfo {
        if selectedURL.pathExtension == "pub" {
            let privateKeyURL = selectedURL.deletingPathExtension()
            if FileManager.default.fileExists(atPath: privateKeyURL.path) {
                return keyInfo(privateKeyURL: privateKeyURL, publicKeyURL: selectedURL)
            }
        }

        return keyInfo(privateKeyURL: selectedURL)
    }

    static func keyInfo(privateKeyURL: URL, publicKeyURL: URL? = nil) -> KeyInfo {
        let resolvedPublicKeyURL = publicKeyURL ?? {
            let candidate = privateKeyURL.appendingPathExtension("pub")
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }()
        let metadata = resolvedPublicKeyURL.flatMap(publicKeyMetadata)

        return KeyInfo(
            name: privateKeyURL.lastPathComponent,
            type: metadata?.type ?? "未知",
            length: metadata?.length ?? "未知",
            privateKeyURL: privateKeyURL,
            publicKeyURL: resolvedPublicKeyURL
        )
    }

    private static func publicKeyMetadata(_ url: URL) -> (type: String, length: String)? {
        guard
            let content = try? String(contentsOf: url, encoding: .utf8),
            let first = content.split(whereSeparator: \.isWhitespace).first
        else { return nil }

        switch String(first) {
        case "ssh-rsa":
            return ("RSA", "2048 bits")
        case "ssh-ed25519":
            return ("ED25519", "256 bits")
        case "ecdsa-sha2-nistp256":
            return ("ECDSA", "256 bits")
        case "ecdsa-sha2-nistp384":
            return ("ECDSA", "384 bits")
        case "ecdsa-sha2-nistp521":
            return ("ECDSA", "521 bits")
        default:
            return (String(first).uppercased(), "未知")
        }
    }
}

struct SSHPrivateKeySelectionView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding private var selectedPath: String
    @State private var keys: [SSHPrivateKeyFilePicker.KeyInfo]
    @State private var selectedID: SSHPrivateKeyFilePicker.KeyInfo.ID?

    init(
        selectedPath: Binding<String>,
        keyDirectory: URL = SSHPrivateKeyFilePicker.defaultDirectoryURL
    ) {
        self._selectedPath = selectedPath

        let currentPath = selectedPath.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var keys = SSHPrivateKeyFilePicker.discoverKeys(in: keyDirectory)
        if !currentPath.isEmpty {
            let currentURL = URL(fileURLWithPath: currentPath)
            if !keys.contains(where: { $0.privateKeyURL.path == currentURL.path }) {
                keys.append(SSHPrivateKeyFilePicker.keyInfo(privateKeyURL: currentURL))
            }
        }

        self._keys = State(initialValue: keys)
        self._selectedID = State(initialValue: keys.first(where: {
            $0.privateKeyURL.path == currentPath
        })?.id ?? keys.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("用户密钥")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                Table(keys, selection: $selectedID) {
                    TableColumn("名称", value: \.name)
                    TableColumn("类型", value: \.type)
                    TableColumn("长度", value: \.length)
                }
                .frame(minWidth: 420, minHeight: 180)

                VStack(spacing: 8) {
                    Button("导入...") {
                        importKey()
                    }

                    Button("移除") {
                        removeSelectedKey()
                    }
                    .disabled(selectedID == nil)
                }
                .frame(width: 88)
            }

            Divider()

            HStack {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("确定") {
                    applySelection()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedKey == nil)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var selectedKey: SSHPrivateKeyFilePicker.KeyInfo? {
        guard let selectedID else { return nil }
        return keys.first { $0.id == selectedID }
    }

    private func importKey() {
        guard let key = SSHPrivateKeyFilePicker.importKey() else { return }
        if !keys.contains(where: { $0.id == key.id }) {
            keys.append(key)
        }
        selectedID = key.id
    }

    private func removeSelectedKey() {
        guard let selectedID else { return }
        keys.removeAll { $0.id == selectedID }
        self.selectedID = keys.first?.id
    }

    private func applySelection() {
        guard let selectedKey else { return }
        selectedPath = selectedKey.privateKeyURL.path
        dismiss()
    }
}
