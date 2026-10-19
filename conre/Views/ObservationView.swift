import SwiftUI
import AppKit

struct ObservationView: View {
    let observer: ActivityObserver
    @State private var applications: [NSRunningApplication] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(observer.status, systemImage: observer.statusKind.symbol)
                Spacer()
                Button(observer.isPaused ? "Resume" : "Pause", action: observer.togglePause)
            }
            Button("Detailed context…") { observer.contextSettingsPresented = true }
            Text("Approve apps below for app/window history. Optional text capture is configured separately in Detailed context.")
                .font(.caption).foregroundStyle(.secondary)
            Text(observer.windowPermission).font(.caption).foregroundStyle(.orange)
            if !observer.sandboxed && !observer.accessibilityGranted {
                Button("Allow window metadata…", action: observer.requestWindowPermission)
            }
            if !observer.accessibilityGranted && !observer.sandboxed {
                Text("Enable Conre in System Settings → Privacy & Security → Accessibility. App-only observation continues without this permission. Permission changes are checked every two seconds.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("APPROVED APPLICATIONS").font(.caption.bold())
                Spacer()
                Button("Refresh apps") { refresh() }
            }
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(applications, id: \.bundleIdentifier) { app in
                        if let id = app.bundleIdentifier {
                            Toggle(app.localizedName ?? id, isOn: Binding(
                                get: { observer.approvedIDs.contains(id) },
                                set: { observer.approve(id, enabled: $0) }))
                        }
                    }
                    ForEach(observer.approvedIDs.subtracting(Set(applications.compactMap(\.bundleIdentifier))).sorted(), id: \.self) { id in
                        Toggle(id, isOn: Binding(get: { observer.approvedIDs.contains(id) }, set: { observer.approve(id, enabled: $0) }))
                    }
                }
            }.frame(height: 130)
            Divider()
            if let latest = observer.log.events.last {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LATEST CAPTURED CONTEXT").font(.caption2.bold()).foregroundStyle(.secondary)
                    Text(latest.windowTitle ?? latest.applicationName).font(.headline).lineLimit(2)
                    Text("\(latest.applicationName) · \(latest.timestamp.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Window title only. Actions within this page are not observed.")
                        .font(.caption).foregroundStyle(.secondary)
                }.textSelection(.enabled)
            }
            HStack {
                Text("Raw observations · \(observer.log.events.count)").font(.headline)
                Spacer()
                Button("Clear log", role: .destructive) { observer.log.clear() }
            }
            if let warning = observer.log.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
            List(observer.log.events.reversed()) { event in
                VStack(alignment: .leading, spacing: 3) {
                    Label(event.windowTitle ?? event.applicationName, systemImage: event.windowTitle == nil ? "app" : "macwindow")
                        .font(.headline)
                    Text(event.windowTitle == nil ? "Window title unavailable · \(event.windowStatus)" : event.applicationName)
                    Text("\(event.bundleID) · PID \(event.processID)").foregroundStyle(.secondary)
                    Text(event.timestamp, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
                }.font(.caption).textSelection(.enabled)
            }
        }.padding(16).onAppear { refresh() }
    }
    private func refresh() {
        var seen = Set<String>()
        applications = NSWorkspace.shared.runningApplications.filter {
            guard $0.activationPolicy == .regular, let id = $0.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return false }
            return seen.insert(id).inserted
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}
