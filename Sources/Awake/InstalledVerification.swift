import AppKit
import AwakeCore
import Darwin

// Invoked only by --verify-installed. Exercises the installed session actions and lifecycle.
@MainActor
enum InstalledVerification {
    static func run(session: SessionController, statusButton: NSButton, root: NSView, shortDuration: TimeInterval?) async {
        do {
            try check(!session.isActive && session.ownedProcessIdentifier == nil, "Launch is inactive")
            try check(NSApp.activationPolicy() == .accessory, "App has no Dock icon")
            try check(root.window?.isVisible == true, "Actual popover window is visible")
            print("WINDOW \(root.window?.windowNumber ?? -1)")
            fflush(stdout)
            await capturePoint(root, state: "inactive")
            let inactiveIcon = statusButton.image?.tiffRepresentation
            session.start()
            try await Task.sleep(for: .milliseconds(200))
            let first = try pid(session)
            try check(session.isActive && session.remainingSeconds == nil, "On starts an indefinite session")
            try check(statusButton.image?.tiffRepresentation != inactiveIcon, "Active menu bar icon changes")
            try check(statusButton.toolTip == "Awake: On", "Menu bar reports On")
            await capturePoint(root, state: "on")
            var previous = first
            for hours in 1...4 {
                session.start(duration: shortDuration ?? Double(hours * 3600), hours: hours)
                try await Task.sleep(for: .milliseconds(100))
                let current = try pid(session)
                try check(kill(previous, 0) == -1, "\(hours)h replaces the previous process")
                try check(session.selectedHours == hours, "\(hours)h is selected")
                try check(session.remainingSeconds != nil && statusButton.toolTip?.contains("remaining") == true,
                          "\(hours)h displays time remaining")
                previous = current
            }
            session.stop()
            try await Task.sleep(for: .milliseconds(100))
            try check(!session.isActive && kill(previous, 0) == -1, "Off immediately stops the owned process")
            try check(statusButton.image?.tiffRepresentation == inactiveIcon, "Inactive menu bar icon returns")
            guard let shortDuration else { throw Failure(message: "Pass --test-duration-seconds for expiry verification") }
            session.start(duration: shortDuration, hours: 1)
            let expiring = try pid(session)
            await capturePoint(root, state: "timed")
            try await Task.sleep(for: .seconds(shortDuration + 0.5))
            try check(!session.isActive && kill(expiring, 0) == -1, "Short timer expires and cleans up")
            try check(session.errorMessage == nil, "Normal timer expiry shows no error")
            session.start()
            let quitting = try pid(session)
            print("QUIT_CHILD \(quitting)")
            fflush(stdout)
            if CommandLine.arguments.contains("--test-crash") { kill(getpid(), SIGKILL) }
            NSApp.terminate(nil)
        } catch {
            print("FAIL \(error)")
            fflush(stdout)
            session.stop()
            NSApp.terminate(nil)
        }
    }

    private static func capturePoint(_ root: NSView, state: String) async {
        guard let directory = ProcessInfo.processInfo.environment["AWAKE_CAPTURE_DIR"] else { return }
        try? await Task.sleep(for: .milliseconds(250))
        root.layoutSubtreeIfNeeded()
        guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let url = URL(fileURLWithPath: directory).appendingPathComponent(state + ".png")
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func pid(_ session: SessionController) throws -> Int32 {
        guard let pid = session.ownedProcessIdentifier, kill(pid, 0) == 0 else {
            throw Failure(message: "Owned caffeinate process is missing")
        }
        return pid
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
        print("PASS \(message)")
        fflush(stdout)
    }

    private struct Failure: Error { let message: String }
}
