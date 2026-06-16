import Foundation
import Testing
@testable import Ghostty

private actor FakeProber: SSHConnectionProbing {
    var results: [String: Bool]
    var calls: [String] = []

    init(results: [String: Bool]) {
        self.results = results
    }

    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        calls.append("\(host):\(port)")
        return results["\(host):\(port)"] ?? false
    }
}

@MainActor
struct SSHReachabilityCheckerTests {
    @Test func successfulProbeTransitionsToOnline() async throws {
        let connection = SSHConnection(name: "API", host: "api.example.com")
        let prober = FakeProber(results: ["api.example.com:22": true])
        let checker = SSHReachabilityChecker(prober: prober)

        checker.refresh(connection)
        #expect(checker.status(for: connection.id) == .checking)

        try await waitUntil {
            checker.status(for: connection.id) == .online
        }
    }

    @Test func failedProbeTransitionsToOffline() async throws {
        let connection = SSHConnection(name: "API", host: "api.example.com")
        let checker = SSHReachabilityChecker(prober: FakeProber(results: ["api.example.com:22": false]))

        checker.refresh(connection)

        try await waitUntil {
            checker.status(for: connection.id) == .offline
        }
    }

    @Test func refreshChecksOnlyProvidedConnections() async throws {
        let group = SSHConnectionGroup(name: "Production")
        let included = SSHConnection(groupID: group.id, name: "API", host: "api.example.com")
        let excluded = SSHConnection(name: "Other", host: "other.example.com")
        let prober = FakeProber(results: ["api.example.com:22": true, "other.example.com:22": true])
        let checker = SSHReachabilityChecker(prober: prober)

        checker.refresh([included])

        try await waitUntil {
            checker.status(for: included.id) == .online
        }
        let calls = await prober.calls
        #expect(calls == ["api.example.com:22"])
        #expect(checker.status(for: excluded.id) == .unknown)
    }

    @Test func duplicateRefreshDoesNotCreateSecondProbeForSameConnection() async throws {
        let connection = SSHConnection(name: "API", host: "api.example.com")
        let prober = FakeProber(results: ["api.example.com:22": true])
        let checker = SSHReachabilityChecker(prober: prober)

        checker.refresh(connection)
        checker.refresh(connection)

        try await waitUntil {
            checker.status(for: connection.id) == .online
        }
        let calls = await prober.calls
        #expect(calls == ["api.example.com:22"])
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        predicate: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for predicate")
    }
}
