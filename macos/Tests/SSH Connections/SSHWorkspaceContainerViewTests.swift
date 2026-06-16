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

    @Test func sidebarPanelCollapseKeepsRailWidthVisible() {
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

        workspace.setSidebarPanelCollapseState(.collapsed)

        #expect(workspace.isSidebarVisible)
        #expect(workspace.currentSidebarWidth == SSHSidebarLayout.collapsedWidth)

        workspace.setSidebarPanelCollapseState(.expanded)

        #expect(workspace.currentSidebarWidth == SSHSidebarLayout.totalWidth)
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
