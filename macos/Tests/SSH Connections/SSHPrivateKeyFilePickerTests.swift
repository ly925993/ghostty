import AppKit
import Testing
@testable import Ghostty

@MainActor
struct SSHPrivateKeyFilePickerTests {
    @Test func configuresPanelForSinglePrivateKeyFileSelection() {
        let panel = NSOpenPanel()

        SSHPrivateKeyFilePicker.configure(panel)

        #expect(panel.title == "选择私钥文件")
        #expect(panel.prompt == "选择")
        #expect(panel.canChooseFiles)
        #expect(!panel.canChooseDirectories)
        #expect(!panel.allowsMultipleSelection)
        #expect(panel.showsHiddenFiles)
        #expect(panel.directoryURL == SSHPrivateKeyFilePicker.defaultDirectoryURL)
    }
}
