import AppKit
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SSHPrivateKeyFilePickerTests {
    @Test func configuresPanelForSinglePrivateKeyFileSelection() {
        let panel = NSOpenPanel()

        SSHPrivateKeyFilePicker.configure(panel)

        #expect(panel.title == "选择用户密钥文件")
        #expect(panel.prompt == "选择")
        #expect(panel.canChooseFiles)
        #expect(!panel.canChooseDirectories)
        #expect(!panel.allowsMultipleSelection)
        #expect(panel.showsHiddenFiles)
        #expect(panel.directoryURL == SSHPrivateKeyFilePicker.defaultDirectoryURL)
    }

    @Test func discoversPublicKeysWithMatchingPrivateKeyPaths() throws {
        let directory = try makeTemporaryDirectory()
        let privateKey = directory.appendingPathComponent("bbway")
        let publicKey = directory.appendingPathComponent("bbway.pub")
        try "private".write(to: privateKey, atomically: true, encoding: .utf8)
        try """
        ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 comment
        """.write(to: publicKey, atomically: true, encoding: .utf8)

        let keys = SSHPrivateKeyFilePicker.discoverKeys(in: directory)

        #expect(keys == [
            SSHPrivateKeyFilePicker.KeyInfo(
                name: "bbway",
                type: "RSA",
                length: "2048 bits",
                privateKeyURL: privateKey,
                publicKeyURL: publicKey
            ),
        ])
    }

    @Test func ignoresPublicKeysWithoutMatchingPrivateKeys() throws {
        let directory = try makeTemporaryDirectory()
        try "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMock comment"
            .write(to: directory.appendingPathComponent("orphan.pub"), atomically: true, encoding: .utf8)

        #expect(SSHPrivateKeyFilePicker.discoverKeys(in: directory).isEmpty)
    }

    @Test func selectedPublicKeyResolvesToMatchingPrivateKeyPath() throws {
        let directory = try makeTemporaryDirectory()
        let privateKey = directory.appendingPathComponent("id_ed25519")
        let publicKey = directory.appendingPathComponent("id_ed25519.pub")
        try "private".write(to: privateKey, atomically: true, encoding: .utf8)
        try "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMock comment"
            .write(to: publicKey, atomically: true, encoding: .utf8)

        let key = SSHPrivateKeyFilePicker.keyInfo(selectedURL: publicKey)

        #expect(key == SSHPrivateKeyFilePicker.KeyInfo(
            name: "id_ed25519",
            type: "ED25519",
            length: "256 bits",
            privateKeyURL: privateKey,
            publicKeyURL: publicKey
        ))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-ssh-key-picker-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
