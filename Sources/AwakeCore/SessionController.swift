import Combine
import Foundation

@MainActor
public final class SessionController: ObservableObject {
    @Published public private(set) var isActive = false
    @Published public private(set) var remainingSeconds: Int?
    @Published public private(set) var selectedHours: Int?
    @Published public private(set) var errorMessage: String?

    private var process: Process?
    private var deadline: Date?
    private var timer: Timer?

    public var ownedProcessIdentifier: Int32? { process?.processIdentifier }

    public var status: String {
        if !isActive { return "Inactive" }
        return remainingSeconds == nil ? "On until you turn it off" : "Timed session running"
    }

    public var remainingTime: String? {
        guard let seconds = remainingSeconds else { return nil }
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    public init() {}

    public func shutdown() { stop() }

    public func start(duration: TimeInterval? = nil, hours: Int? = nil) {
        if let duration, !duration.isFinite || duration <= 0 || duration >= Double(Int.max) {
            stop()
            errorMessage = "Choose a duration greater than zero."
            return
        }
        stop()

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -w releases the assertion even if Awake is force-quit or crashes.
        var arguments = ["-i", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        if let duration { arguments += ["-t", String(Int(ceil(duration)))] }
        child.arguments = arguments
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] terminated in
            Task { @MainActor [weak self] in
                guard let self, self.process === terminated else { return }
                let expired = self.deadline.map { $0 <= Date() } ?? false
                self.clearState()
                if !expired {
                    self.errorMessage = "The awake session ended. Press On to start again."
                }
            }
        }

        let expiresAt = duration.map { Date().addingTimeInterval($0) }
        do {
            try child.run()
            process = child
            deadline = expiresAt
            selectedHours = hours
            remainingSeconds = duration.map { Int(ceil($0)) }
            isActive = true
            if duration != nil {
                let tick = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refreshRemainingTime() }
                }
                timer = tick
                RunLoop.main.add(tick, forMode: .common)
            }
        } catch {
            errorMessage = "Could not start caffeinate: \(error.localizedDescription)"
        }
    }

    public func stop() {
        // Retain the exact Process object. Never find or kill processes by name.
        let child = process
        clearState()
        errorMessage = nil
        if let child, child.isRunning {
            child.terminate()
            child.waitUntilExit()
        }
    }

    public func refreshRemainingTime() {
        guard let deadline else { return }
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            stop()
        } else {
            remainingSeconds = Int(ceil(remaining))
        }
    }

    private func clearState() {
        timer?.invalidate()
        timer = nil
        process = nil
        deadline = nil
        isActive = false
        remainingSeconds = nil
        selectedHours = nil
    }
}
