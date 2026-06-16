import Foundation
import Network

protocol SSHConnectionProbing: Sendable {
    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> Bool
}

struct NetworkSSHConnectionProber: SSHConnectionProbing {
    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue.global(qos: .utility)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let resumeState = SSHProbeResumeState()
            let timeoutWork = DispatchWorkItem {
                connection.cancel()
                resumeState.resumeOnce(continuation, false)
            }

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    timeoutWork.cancel()
                    connection.cancel()
                    resumeState.resumeOnce(continuation, true)
                case .failed, .waiting:
                    timeoutWork.cancel()
                    connection.cancel()
                    resumeState.resumeOnce(continuation, false)
                case .cancelled:
                    timeoutWork.cancel()
                    resumeState.resumeOnce(continuation, false)
                default:
                    break
                }
            }

            let timeoutMilliseconds = Int((timeout * 1_000).rounded(.up))
            queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMilliseconds), execute: timeoutWork)
            connection.start(queue: queue)
        }
    }
}

private final class SSHProbeResumeState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resumeOnce(_ continuation: CheckedContinuation<Bool, Never>, _ value: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: value)
    }
}

@MainActor
final class SSHReachabilityChecker: ObservableObject {
    @Published private(set) var statuses: [SSHConnection.ID: SSHConnectionStatus] = [:]

    private let prober: any SSHConnectionProbing
    private let timeout: TimeInterval
    private let maximumConcurrentChecks: Int
    private var runningTasks: [SSHConnection.ID: Task<Void, Never>] = [:]
    private var pendingConnections: [SSHConnection] = []

    init(
        prober: any SSHConnectionProbing = NetworkSSHConnectionProber(),
        timeout: TimeInterval = 3,
        maximumConcurrentChecks: Int = 4
    ) {
        self.prober = prober
        self.timeout = timeout
        self.maximumConcurrentChecks = max(1, maximumConcurrentChecks)
    }

    func status(for connectionID: SSHConnection.ID) -> SSHConnectionStatus {
        statuses[connectionID] ?? .unknown
    }

    func refresh(_ connections: [SSHConnection]) {
        for connection in connections {
            refresh(connection)
        }
    }

    func refresh(_ connection: SSHConnection) {
        guard runningTasks[connection.id] == nil else { return }
        guard !pendingConnections.contains(where: { $0.id == connection.id }) else { return }

        statuses[connection.id] = .checking
        pendingConnections.append(connection)
        startPendingChecks()
    }

    func cancelAll() {
        for task in runningTasks.values {
            task.cancel()
        }
        runningTasks.removeAll()
        pendingConnections.removeAll()
    }

    private func startPendingChecks() {
        while runningTasks.count < maximumConcurrentChecks && !pendingConnections.isEmpty {
            start(pendingConnections.removeFirst())
        }
    }

    private func start(_ connection: SSHConnection) {
        let prober = self.prober
        let timeout = self.timeout

        runningTasks[connection.id] = Task { [weak self] in
            let isOnline = await prober.probe(
                host: connection.host,
                port: connection.port,
                timeout: timeout
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                self.runningTasks[connection.id] = nil
                self.statuses[connection.id] = isOnline ? .online : .offline
                self.startPendingChecks()
            }
        }
    }
}
