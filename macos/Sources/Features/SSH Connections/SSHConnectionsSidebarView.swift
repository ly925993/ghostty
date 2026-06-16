import AppKit
import Combine
import SwiftUI

@MainActor
protocol SSHTabProviding: AnyObject {
    var tabs: [SSHTabSnapshot] { get }
    func selectTab(id: ObjectIdentifier)
}

struct SSHTabSnapshot: Equatable, Identifiable {
    let id: ObjectIdentifier
    let displayIndex: Int
    let title: String
    let isSelected: Bool

    static func makeTabs(
        windows: [NSWindow],
        selectedWindow: NSWindow?
    ) -> [SSHTabSnapshot] {
        windows.enumerated().map { offset, window in
            let displayIndex = offset + 1
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)

            return SSHTabSnapshot(
                id: ObjectIdentifier(window),
                displayIndex: displayIndex,
                title: title.isEmpty ? "终端 \(displayIndex)" : title,
                isSelected: window === selectedWindow
            )
        }
    }
}

@MainActor
final class SSHWindowTabProvider: ObservableObject, SSHTabProviding {
    var windowProvider: () -> NSWindow? = { nil }

    var tabs: [SSHTabSnapshot] {
        let window = windowProvider()
        return SSHTabSnapshot.makeTabs(
            windows: tabWindows(for: window),
            selectedWindow: selectedWindow(for: window)
        )
    }

    func selectTab(id: ObjectIdentifier) {
        guard let targetWindow = tabWindows(for: windowProvider()).first(where: { ObjectIdentifier($0) == id }) else {
            return
        }

        targetWindow.tabGroup?.selectedWindow = targetWindow
        targetWindow.makeKeyAndOrderFront(nil)
        refresh()
    }

    func refresh() {
        objectWillChange.send()
    }

    private func tabWindows(for window: NSWindow?) -> [NSWindow] {
        guard let window else { return [] }
        if let windows = window.tabGroup?.windows, !windows.isEmpty {
            return windows
        }

        return [window]
    }

    private func selectedWindow(for window: NSWindow?) -> NSWindow? {
        guard let window else { return nil }
        return window.tabGroup?.selectedWindow ?? window
    }
}

@MainActor
final class SSHSidebarAppearance: ObservableObject {
    @Published var config: Ghostty.Config?

    init(config: Ghostty.Config?) {
        self.config = config
    }
}

struct SSHConnectionsSidebarView: View {
    @ObservedObject var viewModel: SSHConnectionsViewModel
    @ObservedObject var appearance: SSHSidebarAppearance
    @ObservedObject var tabProvider: SSHWindowTabProvider
    var onConnect: (SSHConnection) -> Void
    var onClose: () -> Void

    @State private var connectionDraft: SSHConnectionsViewModel.ConnectionDraft?
    @State private var groupDraft: SSHConnectionsViewModel.GroupDraft?
    @State private var pendingDelete: PendingDelete?
    @State private var collapsedGroups: Set<String> = []

    private let tabRefreshTimer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            tabsSection
            search
            content
            divider
            footer
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        .background(theme.background)
        .foregroundStyle(theme.foreground)
        .onReceive(tabRefreshTimer) { _ in
            tabProvider.refresh()
        }
        .sheet(item: $connectionDraft) { draft in
            SSHConnectionEditorView(viewModel: viewModel, draft: draft)
        }
        .sheet(item: $groupDraft) { draft in
            SSHGroupEditorView(viewModel: viewModel, draft: draft)
        }
        .alert("SSH 连接", isPresented: Binding(
            get: { viewModel.alertMessage != nil },
            set: { if !$0 { viewModel.alertMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .alert("删除 SSH 项目？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { pendingDelete in
            Button(pendingDelete.buttonTitle, role: .destructive) {
                confirmDelete(pendingDelete)
            }
            Button("取消", role: .cancel) {}
        } message: { pendingDelete in
            Text(pendingDelete.message)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("SSH 连接")
                .font(.headline)
            Spacer()
            Button {
                viewModel.refreshVisibleConnections()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新状态")
            .buttonStyle(.borderless)

            Button {
                connectionDraft = viewModel.connectionDraft()
            } label: {
                Image(systemName: "plus")
            }
            .help("添加服务器")
            .buttonStyle(.borderless)

            Button {
                onClose()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("隐藏 SSH 连接")
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var search: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryForeground)
            TextField("搜索服务器", text: $viewModel.searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.searchBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.divider, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(10)
    }

    @ViewBuilder
    private var tabsSection: some View {
        let tabs = tabProvider.tabs
        if !tabs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("页签")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.secondaryForeground)
                    Spacer()
                    Text("\(tabs.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.secondaryForeground)
                }
                .padding(.horizontal, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(tabs) { tab in
                            tabRow(tab)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: CGFloat(min(tabs.count, 4)) * 40 + 4)
                .background(theme.background)
            }
            .padding(.vertical, 8)

            divider
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.contentState {
        case .emptyLibrary:
            emptyState(
                title: "暂无服务器",
                systemImage: "server.rack",
                actionTitle: "添加服务器"
            ) {
                connectionDraft = viewModel.connectionDraft()
            }

        case .noResults:
            emptyState(
                title: "没有匹配结果",
                systemImage: "magnifyingglass",
                actionTitle: "添加服务器"
            ) {
                connectionDraft = viewModel.connectionDraft()
            }

        case .content:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(viewModel.sections) { section in
                        let isExpanded = isSectionExpanded(section)

                        VStack(alignment: .leading, spacing: 2) {
                            Button {
                                toggleSection(section)
                            } label: {
                                sectionHeader(section, isExpanded: isExpanded)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                sectionContextMenu(section)
                            }

                            if isExpanded {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(section.connections) { connection in
                                        connectionRow(connection)
                                    }
                                }
                                .padding(.leading, 18)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(theme.background)
        }
    }

    private func tabRow(_ tab: SSHTabSnapshot) -> some View {
        Button {
            tabProvider.selectTab(id: tab.id)
        } label: {
            HStack(spacing: 8) {
                Text("\(tab.displayIndex)")
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .frame(width: 22, height: 22)
                    .background(tab.isSelected ? theme.activePillBackground : theme.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text("第 \(tab.displayIndex) 个页签")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryForeground)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if tab.isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(theme.foreground)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tab.isSelected ? theme.selectedBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.title), 第 \(tab.displayIndex) 个页签")
    }

    @ViewBuilder
    private func sectionContextMenu(_ section: SSHConnectionsViewModel.Section) -> some View {
        if let group = section.group {
            Button("添加服务器") {
                connectionDraft = viewModel.connectionDraft(for: group.id)
            }
            Button("编辑分组") {
                groupDraft = viewModel.groupDraft(for: group)
            }
            Button("删除分组", role: .destructive) {
                pendingDelete = .group(group)
            }
            Divider()
        }
        Button("刷新状态") {
            viewModel.refresh(section)
        }
    }

    private func sectionHeader(
        _ section: SSHConnectionsViewModel.Section,
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12)
                .foregroundStyle(theme.secondaryForeground)
            Image(systemName: section.group == nil ? "tray" : "folder")
                .foregroundStyle(theme.secondaryForeground)
            Text(section.title)
                .lineLimit(1)
            Spacer()
            Text("\(section.connections.count)")
                .foregroundStyle(theme.secondaryForeground)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func connectionRow(_ connection: SSHConnection) -> some View {
        Button {
            onConnect(connection)
        } label: {
            HStack(spacing: 8) {
                statusIcon(for: connection)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .lineLimit(1)
                    Text(connectionSubtitle(connection))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryForeground)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("连接") {
                onConnect(connection)
            }
            Button("编辑服务器") {
                connectionDraft = viewModel.connectionDraft(for: connection)
            }
            Button("刷新状态") {
                viewModel.refresh(connection)
            }
            Divider()
            Button("删除服务器", role: .destructive) {
                pendingDelete = .connection(connection)
            }
        }
        .accessibilityLabel("\(connection.name), \(viewModel.status(for: connection).label)")
    }

    private var footer: some View {
        HStack {
            Button {
                groupDraft = viewModel.groupDraft()
            } label: {
                Label("分组", systemImage: "folder.badge.plus")
            }

            Spacer()

            Button {
                connectionDraft = viewModel.connectionDraft()
            } label: {
                Label("服务器", systemImage: "server.rack")
            }
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .padding(10)
    }

    private func emptyState(
        title: String,
        systemImage: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(theme.secondaryForeground)
            Text(title)
                .font(.headline)
            Button(actionTitle, action: action)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    private func statusIcon(for connection: SSHConnection) -> some View {
        let status = viewModel.status(for: connection)
        return Image(systemName: status.systemImage)
            .foregroundStyle(status.color)
            .help(status.label)
            .accessibilityLabel(status.label)
            .frame(width: 16, height: 16)
    }

    private func connectionSubtitle(_ connection: SSHConnection) -> String {
        let destination = connection.username.isEmpty
            ? connection.host
            : "\(connection.username)@\(connection.host)"
        return connection.port == 22 ? destination : "\(destination):\(connection.port)"
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(height: 0.5)
    }

    private var theme: SSHSidebarTheme {
        SSHSidebarTheme(config: appearance.config)
    }

    private func isSectionExpanded(_ section: SSHConnectionsViewModel.Section) -> Bool {
        !collapsedGroups.contains(section.id) || !viewModel.normalizedSearchText.isEmpty
    }

    private func toggleSection(_ section: SSHConnectionsViewModel.Section) {
        if isSectionExpanded(section) {
            collapsedGroups.insert(section.id)
        } else {
            collapsedGroups.remove(section.id)
        }
    }

    private func confirmDelete(_ pendingDelete: PendingDelete) {
        switch pendingDelete {
        case .connection(let connection):
            _ = viewModel.deleteConnection(connection)
        case .group(let group):
            _ = viewModel.deleteGroup(group)
        }

        self.pendingDelete = nil
    }

    private enum PendingDelete: Identifiable {
        case connection(SSHConnection)
        case group(SSHConnectionGroup)

        var id: String {
            switch self {
            case .connection(let connection):
                "connection-\(connection.id.uuidString)"
            case .group(let group):
                "group-\(group.id.uuidString)"
            }
        }

        var buttonTitle: String {
            switch self {
            case .connection:
                "删除服务器"
            case .group:
                "删除分组"
            }
        }

        var message: String {
            switch self {
            case .connection:
                "此服务器将从 SSH 连接库中移除。"
            case .group:
                "如果此分组下没有服务器，将删除该分组。"
            }
        }
    }
}

struct SSHSidebarTheme {
    let background: Color
    let foreground: Color
    let secondaryForeground: Color
    let searchBackground: Color
    let rowBackground: Color
    let selectedBackground: Color
    let activePillBackground: Color
    let divider: Color

    init(config: Ghostty.Config?) {
        let background = config?.backgroundColor ?? Color(nsColor: .controlBackgroundColor)
        let foreground = config?.foregroundColor ?? Color.primary

        self.background = background
        self.foreground = foreground
        secondaryForeground = foreground.opacity(0.68)
        divider = config?.splitDividerColor ?? foreground.opacity(0.22)
        searchBackground = foreground.opacity(0.06)
        rowBackground = foreground.opacity(0.045)
        selectedBackground = foreground.opacity(0.12)
        activePillBackground = foreground.opacity(0.18)
    }
}
