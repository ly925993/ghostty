import Foundation

struct SSHConnectionCommandBuilder {
    enum ValidationError: Error, Equatable, LocalizedError {
        case emptyHost

        var errorDescription: String? {
            switch self {
            case .emptyHost:
                "请输入主机地址。"
            }
        }
    }

    func buildConfiguration(for connection: SSHConnection) throws -> Ghostty.SurfaceConfiguration {
        let command = try buildCommand(for: connection)
        var configuration = Ghostty.SurfaceConfiguration()
        configuration.command = command
        return configuration
    }

    func buildCommand(for connection: SSHConnection) throws -> String {
        let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw ValidationError.emptyHost
        }

        var segments = ["ssh"]
        if connection.port != 22 {
            segments.append("-p")
            segments.append(Ghostty.Shell.quote(String(connection.port)))
        }

        let privateKeyPath = connection.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !privateKeyPath.isEmpty {
            segments.append("-i")
            segments.append(Ghostty.Shell.quote(privateKeyPath))
        }

        let username = connection.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = username.isEmpty ? host : "\(username)@\(host)"
        segments.append(Ghostty.Shell.quote(destination))

        return segments.joined(separator: " ")
    }
}
