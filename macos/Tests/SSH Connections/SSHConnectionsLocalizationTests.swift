import Testing
@testable import Ghostty

struct SSHConnectionsLocalizationTests {
    @Test func statusLabelsUseChineseText() {
        #expect(SSHConnectionStatus.online.label == "在线")
        #expect(SSHConnectionStatus.offline.label == "离线")
        #expect(SSHConnectionStatus.checking.label == "检测中")
        #expect(SSHConnectionStatus.unknown.label == "未知")
    }

    @Test func defaultSectionTitleUsesChineseText() {
        let section = SSHConnectionsViewModel.Section(
            id: "ungrouped",
            group: nil,
            connections: []
        )

        #expect(section.title == "未分组")
    }
}
