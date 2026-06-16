import SwiftUI

enum SSHConnectionStatus: String, Codable, Equatable, Sendable {
    case unknown
    case checking
    case online
    case offline

    var label: String {
        switch self {
        case .unknown:
            "未知"
        case .checking:
            "检测中"
        case .online:
            "在线"
        case .offline:
            "离线"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown:
            "questionmark.circle"
        case .checking:
            "clock"
        case .online:
            "checkmark.circle.fill"
        case .offline:
            "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .unknown:
            Color.secondary
        case .checking:
            Color.accentColor
        case .online:
            Color.green
        case .offline:
            Color.red
        }
    }
}
