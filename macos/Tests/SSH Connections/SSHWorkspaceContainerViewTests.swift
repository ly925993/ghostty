import SwiftUI
import Testing
@testable import Ghostty

@MainActor
struct SSHWorkspaceContainerViewTests {
    @Test func sidebarIsVisibleByDefaultForSSHWorkspace() {
        let terminalView = TerminalViewContainer {
            EmptyView()
        }
        let viewModel = SSHConnectionsViewModel(
            store: SSHConnectionStore(fileURL: temporaryFileURL()),
            reachabilityChecker: SSHReachabilityChecker(prober: FakeWorkspaceProber())
        )

        let workspace = SSHWorkspaceContainerView(
            terminalView: terminalView,
            viewModel: viewModel
        )

        #expect(workspace.isSidebarVisible)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-ssh-workspace-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("ssh-connections.json")
    }
}

private actor FakeWorkspaceProber: SSHConnectionProbing {
    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        false
    }
}
