import AppKit
import SwiftUI
import Testing
@testable import Ghostty

@MainActor
struct SSHConnectionsSidebarViewTests {
    @Test func themeUsesConfiguredTerminalColorsDirectly() {
        let background = Color(red: 0.12, green: 0.18, blue: 0.24)
        let foreground = Color(red: 0.86, green: 0.88, blue: 0.90)
        let divider = Color(red: 0.20, green: 0.24, blue: 0.28)
        let config = SidebarMockConfig(
            backgroundColor: background,
            foregroundColor: foreground,
            splitDividerColor: divider
        )

        let theme = SSHSidebarTheme(config: config)

        #expect(NSColor(theme.background).hexString == NSColor(background).hexString)
        #expect(NSColor(theme.foreground).hexString == NSColor(foreground).hexString)
        #expect(NSColor(theme.divider).hexString == NSColor(divider).hexString)
    }

    @Test func themeDerivesNavigationChromeFromConfiguredBackground() throws {
        let background = Color(red: 0.12, green: 0.18, blue: 0.24)
        let foreground = Color(red: 0.86, green: 0.88, blue: 0.90)
        let config = SidebarMockConfig(
            backgroundColor: background,
            foregroundColor: foreground,
            splitDividerColor: Color(red: 0.20, green: 0.24, blue: 0.28)
        )

        let theme = SSHSidebarTheme(config: config)
        let backgroundColor = try #require(NSColor(background).usingColorSpace(.sRGB))
        let railColor = try #require(NSColor(theme.railBackground).usingColorSpace(.sRGB))
        let headerColor = try #require(NSColor(theme.panelHeaderBackground).usingColorSpace(.sRGB))
        let rowColor = try #require(NSColor(theme.rowBackground).usingColorSpace(.sRGB))

        #expect(railColor.luminance < backgroundColor.luminance)
        #expect(headerColor.luminance < backgroundColor.luminance)
        #expect(rowColor.luminance > backgroundColor.luminance)
    }

    @Test func sidebarLayoutKeepsRailAndTreeReadable() {
        #expect(SSHSidebarLayout.railWidth == 56)
        #expect(SSHSidebarLayout.totalWidth == 340)
        #expect(SSHSidebarLayout.collapsedWidth == SSHSidebarLayout.railWidth)
        #expect(SSHWorkspaceContainerView.sidebarWidth == SSHSidebarLayout.totalWidth)
    }

    @Test func collapseButtonKeepsNavigationRailAvailable() {
        #expect(SSHSidebarCollapseState.expanded.width == SSHSidebarLayout.totalWidth)
        #expect(SSHSidebarCollapseState.collapsed.width == SSHSidebarLayout.collapsedWidth)
        #expect(SSHSidebarCollapseState.expanded.toggled == .collapsed)
        #expect(SSHSidebarCollapseState.collapsed.toggled == .expanded)
    }

    @Test func tabSnapshotsPreserveOrderAndSelectedWindow() {
        let first = NSWindow()
        first.title = "api.example.com"
        let second = NSWindow()
        second.title = "db.example.com"

        let tabs = SSHTabSnapshot.makeTabs(
            windows: [first, second],
            selectedWindow: second
        )

        #expect(tabs.map(\.title) == ["api.example.com", "db.example.com"])
        #expect(tabs.map(\.displayIndex) == [1, 2])
        #expect(tabs.map(\.isSelected) == [false, true])
    }

    @Test func emptyWindowTitleFallsBackToNumberedTerminalTitle() throws {
        let window = NSWindow()

        let tab = try #require(SSHTabSnapshot.makeTabs(
            windows: [window],
            selectedWindow: window
        ).first)

        #expect(tab.title == "终端 1")
        #expect(tab.isSelected)
    }

    @Test func providerSelectsWindowByIdentifier() {
        let first = NSWindow()
        let second = NSWindow()
        let provider = StaticSSHTabProvider(windows: [first, second], selectedWindow: first)

        provider.selectTab(id: ObjectIdentifier(second))

        #expect(provider.selectedWindow === second)
    }

    @Test func sidebarPanelsUseStableChineseNavigationOrder() {
        #expect(SSHSidebarPanel.allCases == [.tabs, .servers])
        #expect(SSHSidebarPanel.defaultPanel == .servers)
        #expect(SSHSidebarPanel.tabs.title == "页签")
        #expect(SSHSidebarPanel.servers.title == "服务器")
    }

    @Test func tabFilteringMatchesTitleCaseInsensitively() {
        let tabs = [
            SSHTabSnapshot(id: ObjectIdentifier(NSWindow()), displayIndex: 1, title: "xl-shop-b2c", isSelected: false),
            SSHTabSnapshot(id: ObjectIdentifier(NSWindow()), displayIndex: 2, title: "Ghostty", isSelected: true),
        ]

        #expect(SSHTabSnapshot.filtered(tabs, query: "ghost").map(\.title) == ["Ghostty"])
        #expect(SSHTabSnapshot.filtered(tabs, query: " ").map(\.title) == ["xl-shop-b2c", "Ghostty"])
    }
}

private final class SidebarMockConfig: Ghostty.Config {
    private let mockedBackgroundColor: Color
    private let mockedForegroundColor: Color
    private let mockedSplitDividerColor: Color

    init(
        backgroundColor: Color,
        foregroundColor: Color,
        splitDividerColor: Color
    ) {
        self.mockedBackgroundColor = backgroundColor
        self.mockedForegroundColor = foregroundColor
        self.mockedSplitDividerColor = splitDividerColor
        super.init(config: nil)
    }

    override var backgroundColor: Color {
        mockedBackgroundColor
    }

    override var foregroundColor: Color {
        mockedForegroundColor
    }

    override var splitDividerColor: Color {
        mockedSplitDividerColor
    }
}

private final class StaticSSHTabProvider: SSHTabProviding {
    private let windows: [NSWindow]
    private(set) var selectedWindow: NSWindow?

    init(windows: [NSWindow], selectedWindow: NSWindow?) {
        self.windows = windows
        self.selectedWindow = selectedWindow
    }

    var tabs: [SSHTabSnapshot] {
        SSHTabSnapshot.makeTabs(windows: windows, selectedWindow: selectedWindow)
    }

    func selectTab(id: ObjectIdentifier) {
        selectedWindow = windows.first { ObjectIdentifier($0) == id }
    }
}
