import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

struct MenuShortcutManagerTests {
    @Test(.bug("https://github.com/ghostty-org/ghostty/issues/779", id: 779))
    func unbindShouldDiscardDefault() async throws {
        let config = try TemporaryConfig("keybind = super+d=unbind")

        let item = NSMenuItem(title: "Split Right", action: #selector(BaseTerminalController.splitRight(_:)), keyEquivalent: "d")
        item.keyEquivalentModifierMask = .command
        let manager = await Ghostty.MenuShortcutManager()
        await manager.reset()
        await manager.syncMenuShortcut(config, action: "new_split:right", menuItem: item)

        #expect(item.keyEquivalent.isEmpty)
        #expect(item.keyEquivalentModifierMask.isEmpty)

        try config.reload("")

        await manager.reset()
        await manager.syncMenuShortcut(config, action: "new_split:right", menuItem: item)

        #expect(item.keyEquivalent == "d")
        #expect(item.keyEquivalentModifierMask == .command)
    }

    @Test(.bug("https://github.com/ghostty-org/ghostty/issues/11396", id: 11396))
    func overrideDefault() async throws {
        let config = try TemporaryConfig("keybind=super+h=goto_split:left")

        let hideItem = NSMenuItem(title: "Hide Ghostty", action: "hide:", keyEquivalent: "h")
        hideItem.keyEquivalentModifierMask = .command

        let goToLeftItem = NSMenuItem(title: "Select Split Left", action: "splitMoveFocusLeft:", keyEquivalent: "")

        let manager = await Ghostty.MenuShortcutManager()
        await manager.reset()

        await manager.syncMenuShortcut(config, action: nil, menuItem: hideItem)
        await manager.syncMenuShortcut(config, action: "goto_split:left", menuItem: goToLeftItem)

        #expect(hideItem.keyEquivalent.isEmpty)
        #expect(hideItem.keyEquivalentModifierMask.isEmpty)

        #expect(goToLeftItem.keyEquivalent == "h")
        #expect(goToLeftItem.keyEquivalentModifierMask == .command)
    }

    @Test
    func sshSidebarShortcutUsesNonDefaultCombination() async throws {
        let config = try TemporaryConfig("")
        let shortcut = KeyboardShortcut("s", modifiers: [.command, .option, .shift])

        let item = NSMenuItem(title: "SSH 连接", action: "toggleSSHConnectionsSidebar:", keyEquivalent: "")

        let manager = await Ghostty.MenuShortcutManager()
        await manager.reset()

        await manager.syncMenuShortcut(config, action: "toggle_ssh_connections_sidebar", menuItem: item)

        #expect(item.keyEquivalent == "s")
        #expect(item.keyEquivalentModifierMask == [.command, .option, .shift])
        #expect(config.keyboardShortcut(for: "toggle_ssh_connections_sidebar") == shortcut)
        #expect(config.keyboardShortcut(for: "new_window") != shortcut)
        #expect(config.keyboardShortcut(for: "new_tab") != shortcut)
        #expect(config.keyboardShortcut(for: "reload_config") != shortcut)
        #expect(config.keyboardShortcut(for: "toggle_command_palette") != shortcut)
        #expect(config.keyboardShortcut(for: "toggle_quick_terminal") != shortcut)
        #expect(config.keyboardShortcut(for: "toggle_visibility") != shortcut)
    }

    @Test
    func sshSidebarShortcutUsesConfiguredKeybind() async throws {
        let config = try TemporaryConfig("keybind = cmd+option+j=toggle_ssh_connections_sidebar")

        let item = NSMenuItem(title: "SSH 连接", action: "toggleSSHConnectionsSidebar:", keyEquivalent: "s")
        item.keyEquivalentModifierMask = [.command, .option, .shift]

        let manager = await Ghostty.MenuShortcutManager()
        await manager.reset()

        await manager.syncMenuShortcut(config, action: "toggle_ssh_connections_sidebar", menuItem: item)

        #expect(item.keyEquivalent == "j")
        #expect(item.keyEquivalentModifierMask == [.command, .option])
    }
}
