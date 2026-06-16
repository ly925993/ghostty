import SwiftUI

struct SSHConnectionsSidebarView: View {
    @ObservedObject var viewModel: SSHConnectionsViewModel
    var config: Ghostty.Config?
    var onConnect: (SSHConnection) -> Void
    var onClose: () -> Void

    @State private var connectionDraft: SSHConnectionsViewModel.ConnectionDraft?
    @State private var groupDraft: SSHConnectionsViewModel.GroupDraft?
    @State private var pendingDelete: PendingDelete?
    @State private var expandedGroups: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            search
            content
            divider
            footer
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        .background(theme.background)
        .foregroundStyle(theme.foreground)
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
                .foregroundStyle(.secondary)
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
            List {
                ForEach(viewModel.sections) { section in
                    Section {
                        DisclosureGroup(
                            isExpanded: bindingForSection(section)
                        ) {
                            ForEach(section.connections) { connection in
                                connectionRow(connection)
                            }
                        } label: {
                            sectionHeader(section)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
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
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Button(actionTitle, action: action)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeader(_ section: SSHConnectionsViewModel.Section) -> some View {
        HStack {
            Image(systemName: section.group == nil ? "tray" : "folder")
            Text(section.title)
                .lineLimit(1)
            Spacer()
            Text("\(section.connections.count)")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .contextMenu {
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
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
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
        SSHSidebarTheme(config: config)
    }

    private func bindingForSection(_ section: SSHConnectionsViewModel.Section) -> Binding<Bool> {
        Binding {
            expandedGroups.contains(section.id) || !viewModel.normalizedSearchText.isEmpty
        } set: { isExpanded in
            if isExpanded {
                expandedGroups.insert(section.id)
            } else {
                expandedGroups.remove(section.id)
            }
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

private struct SSHSidebarTheme {
    let background: Color
    let foreground: Color
    let searchBackground: Color
    let divider: Color

    init(config: Ghostty.Config?) {
        background = config?.backgroundColor ?? Color(nsColor: .controlBackgroundColor)
        foreground = config?.foregroundColor ?? Color.primary
        divider = config?.splitDividerColor ?? Color(nsColor: .separatorColor)
        searchBackground = config?.backgroundColor.opacity(0.88) ?? Color(nsColor: .textBackgroundColor)
    }
}
