import AppKit
import AwakeCore
import Combine
import SwiftUI

@main
struct AwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let session = SessionController()
    private let popover = NSPopover()
    private var item: NSStatusItem?
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let identity = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identity)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--test-appearance"),
           CommandLine.arguments.indices.contains(index + 1) {
            let name: NSAppearance.Name = CommandLine.arguments[index + 1] == "light" ? .aqua : .darkAqua
            NSApp.appearance = NSAppearance(named: name)
        }
        popover.behavior = CommandLine.arguments.contains("--show-popover") ? .applicationDefined : .transient
        popover.appearance = NSApp.appearance
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: AwakePopover(
            session: session,
            testDuration: Self.testDuration,
            quit: { NSApp.terminate(nil) }
        ))
        popover.contentSize = NSSize(width: 288, height: 282)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "Awake"
        item = statusItem
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp])
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.setAccessibilityLabel("Awake")
        observation = session.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateIcon() }
        }
        updateIcon()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        if CommandLine.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.popover.isShown else { return }
                self.togglePopover()
            }
        }
        if CommandLine.arguments.contains("--verify-installed") {
            Task { @MainActor [self] in
                try? await Task.sleep(for: .seconds(1))
                if !popover.isShown { togglePopover() }
                await InstalledVerification.run(
                    session: session,
                    statusButton: item!.button!,
                    root: popover.contentViewController!.view,
                    shortDuration: Self.testDuration
                )
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.shutdown()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePopover() }
        return false
    }

    private func updateIcon() {
        let symbol = session.isActive ? "sun.max.fill" : "moon.zzz"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Awake")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        image?.isTemplate = true
        item?.button?.image = image
        let value = session.isActive ? (session.remainingTime.map { "\($0) remaining" } ?? "On") : "Off"
        item?.button?.toolTip = "Awake: \(value)"
        item?.button?.setAccessibilityValue(value)
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            popover.contentSize = NSSize(width: 288, height: max(282, view.fittingSize.height))
        }
    }

    @objc private func didWake() { session.refreshRemainingTime() }

    @objc private func togglePopover() {
        guard let button = item?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            session.refreshRemainingTime()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.title = "Awake"
                window.makeKey()
            }
        }
    }

    // Explicit local verification hook. Normal launches always use full hours.
    private static var testDuration: TimeInterval? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--test-duration-seconds"),
              arguments.indices.contains(index + 1),
              let seconds = TimeInterval(arguments[index + 1]),
              seconds.isFinite, (1...30).contains(seconds) else { return nil }
        return seconds
    }
}

struct AwakePopover: View {
    @ObservedObject var session: SessionController
    let testDuration: TimeInterval?
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: session.isActive ? "sun.max.fill" : "moon.zzz")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(session.isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Awake").font(.headline)
                    Text(session.isActive ? "Keeping your Mac awake" : "Your Mac can sleep normally")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                stateButton("On", selected: session.isActive && session.remainingSeconds == nil) {
                    session.start()
                }
                stateButton("Off", selected: !session.isActive) { session.stop() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("KEEP AWAKE FOR").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(1...4, id: \.self) { hours in
                        stateButton("\(hours)h", selected: session.selectedHours == hours) {
                            session.start(duration: testDuration ?? Double(hours * 3600), hours: hours)
                        }
                        .accessibilityLabel("\(hours) hour\(hours == 1 ? "" : "s")")
                    }
                }
            }

            HStack(spacing: 6) {
                Circle().fill(session.isActive ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6).accessibilityHidden(true)
                if let remaining = session.remainingTime {
                    Text("\(remaining) remaining").monospacedDigit()
                } else {
                    Text(session.status)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            if let error = session.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                Spacer()
                Button("Quit Awake", action: quit)
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .font(.caption).keyboardShortcut("q")
            }
        }
        .padding(20)
        .frame(width: 288)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func stateButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity).frame(height: 24)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : nil)
        .accessibilityValue(selected ? "Selected" : "")
    }
}
