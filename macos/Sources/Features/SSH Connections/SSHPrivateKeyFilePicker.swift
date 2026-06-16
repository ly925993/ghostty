import AppKit
import Foundation

@MainActor
enum SSHPrivateKeyFilePicker {
    static var defaultDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
    }

    static func configure(_ panel: NSOpenPanel) {
        panel.title = "选择私钥文件"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = defaultDirectoryURL
    }

    static func select() -> String? {
        let panel = NSOpenPanel()
        configure(panel)

        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }
}
