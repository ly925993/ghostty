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

    static func filtered(_ tabs: [SSHTabSnapshot], query: String) -> [SSHTabSnapshot] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return tabs }

        return tabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}

enum SSHSidebarPanel: String, CaseIterable, Equatable, Identifiable {
    case tabs
    case servers

    static let defaultPanel: SSHSidebarPanel = .servers

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tabs:
            "页签"
        case .servers:
            "服务器"
        }
    }

    var systemImage: String {
        switch self {
        case .tabs:
            "rectangle.stack"
        case .servers:
            "server.rack"
        }
    }
}

enum SSHSidebarLayout {
    static let railWidth: CGFloat = 56
    static let totalWidth: CGFloat = 340
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
    @State private var selectedPanel: SSHSidebarPanel = .defaultPanel
    @State private var tabSearchText = ""

    private let tabRefreshTimer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            rail
            dividerVertical
            mainPanel
        }
        .frame(
            minWidth: SSHSidebarLayout.totalWidth,
            idealWidth: SSHSidebarLayout.totalWidth,
            maxWidth: SSHSidebarLayout.totalWidth
        )
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

    private var rail: some View {
        VStack(spacing: 8) {
            ForEach(SSHSidebarPanel.allCases) { panel in
                railButton(panel)
            }

            Spacer(minLength: 0)

            Button {
                onClose()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 40, height: 36)
            }
            .help("隐藏 SSH 连接")
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondaryForeground)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: SSHSidebarLayout.railWidth)
        .background(theme.railBackground)
    }

    private func railButton(_ panel: SSHSidebarPanel) -> some View {
        let isSelected = selectedPanel == panel
        return Button {
            selectedPanel = panel
        } label: {
            VStack(spacing: 4) {
                Image(systemName: panel.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                Text(panel.title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .frame(width: 44, height: 48)
            .background(isSelected ? theme.railSelectedBackground : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.foreground)
                        .frame(width: 3, height: 28)
                        .offset(x: -4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? theme.foreground : theme.secondaryForeground)
        .help(panel.title)
        .accessibilityLabel(panel.title)
    }

    @ViewBuilder
    private var mainPanel: some View {
        switch selectedPanel {
        case .tabs:
            tabsPanel
        case .servers:
            serversPanel
        }
    }

    private var serversPanel: some View {
        VStack(spacing: 0) {
            header(title: SSHSidebarPanel.servers.title, mode: .servers)
            search
            content
            divider
            footer
        }
        .background(theme.background)
    }

    private var tabsPanel: some View {
        VStack(spacing: 0) {
            header(title: SSHSidebarPanel.tabs.title, mode: .tabs)
            tabSearch
            tabsContent
        }
        .background(theme.background)
    }

    private func header(title: String, mode: SSHSidebarPanel) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(mode == .servers ? "SSH 连接管理" : "当前窗口页签")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryForeground)
            }
            Spacer()

            switch mode {
            case .tabs:
                Button {
                    tabProvider.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新页签")
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .background(theme.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            case .servers:
                Button {
                    viewModel.refreshVisibleConnections()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新状态")
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .background(theme.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    connectionDraft = viewModel.connectionDraft()
                } label: {
                    Image(systemName: "plus")
                }
                .help("添加服务器")
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .background(theme.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(theme.panelHeaderBackground)
    }

    private var search: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryForeground)
            TextField("搜索服务器", text: $viewModel.searchText)
                .textFieldStyle(.plain)
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(theme.searchBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(theme.divider, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .padding(10)
    }

    @ViewBuilder
    private var tabsContent: some View {
        let tabs = SSHTabSnapshot.filtered(tabProvider.tabs, query: tabSearchText)
        if tabs.isEmpty {
            emptyState(
                title: tabSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "暂无页签" : "没有匹配页签",
                systemImage: "rectangle.stack",
                actionTitle: "刷新"
            ) {
                tabProvider.refresh()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(tabs) { tab in
                        tabRow(tab)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(theme.background)
        }
    }

    private var tabSearch: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryForeground)
            TextField("搜索页签", text: $tabSearchText)
                .textFieldStyle(.plain)
            Text("\(SSHTabSnapshot.filtered(tabProvider.tabs, query: tabSearchText).count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondaryForeground)
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(theme.searchBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(theme.divider, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(viewModel.sections) { section in
                        let isExpanded = isSectionExpanded(section)

                        VStack(alignment: .leading, spacing: 3) {
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
                                .padding(.leading, 8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
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
                    .frame(width: 24, height: 22)
                    .background(tab.isSelected ? theme.activePillBackground : theme.badgeBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

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
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tab.isSelected ? theme.selectedBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
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
                .frame(width: 10)
                .foregroundStyle(theme.secondaryForeground)
            Image(systemName: section.group == nil ? "tray" : "folder")
                .foregroundStyle(theme.secondaryForeground)
                .frame(width: 16)
            Text(section.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
            Spacer()
            Text("\(section.connections.count)")
                .foregroundStyle(theme.secondaryForeground)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func connectionRow(_ connection: SSHConnection) -> some View {
        Button {
            onConnect(connection)
        } label: {
            HStack(spacing: 8) {
                statusIcon(for: connection)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(connectionSubtitle(connection))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryForeground)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
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

    private var dividerVertical: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(width: 0.5)
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
    let railBackground: Color
    let panelHeaderBackground: Color
    let foreground: Color
    let secondaryForeground: Color
    let searchBackground: Color
    let sectionBackground: Color
    let rowBackground: Color
    let selectedBackground: Color
    let railSelectedBackground: Color
    let badgeBackground: Color
    let activePillBackground: Color
    let divider: Color

    init(config: Ghostty.Config?) {
        let background = config?.backgroundColor ?? Color(nsColor: .controlBackgroundColor)
        let foreground = config?.foregroundColor ?? Color.primary
        let baseColor = NSColor(background)
        let isLightBackground = baseColor.isLightColor
        let darkerAmount: CGFloat = isLightBackground ? 0.05 : 0.12
        let lighterAmount: Double = isLightBackground ? -0.035 : 0.055
        let chromeColor = Color(baseColor.darken(by: darkerAmount))
        let lift = foreground.opacity(isLightBackground ? 0.08 : 0.09)

        self.background = background
        railBackground = chromeColor
        panelHeaderBackground = chromeColor
        self.foreground = foreground
        secondaryForeground = foreground.opacity(0.68)
        divider = config?.splitDividerColor ?? foreground.opacity(0.22)
        searchBackground = background.adjustedBrightness(by: lighterAmount)
        sectionBackground = background.adjustedBrightness(by: lighterAmount * 0.55)
        rowBackground = background.adjustedBrightness(by: lighterAmount)
        selectedBackground = background.adjustedBrightness(by: isLightBackground ? -0.08 : 0.12)
        railSelectedBackground = lift
        badgeBackground = lift
        activePillBackground = foreground.opacity(0.18)
    }
}

private extension Color {
    func adjustedBrightness(by amount: Double) -> Color {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let red = min(max(Double(color.redComponent) + amount, 0), 1)
        let green = min(max(Double(color.greenComponent) + amount, 0), 1)
        let blue = min(max(Double(color.blueComponent) + amount, 0), 1)

        return Color(red: red, green: green, blue: blue, opacity: Double(color.alphaComponent))
    }
}
