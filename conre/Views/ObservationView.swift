import SwiftUI
import AppKit

struct ObservationView: View {
    let observer: ActivityObserver
    @State private var apps: [AppChoice] = []
    private struct AppChoice: Identifiable { let id: String; let name: String }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Apps & permissions").font(.title2.bold())
                Spacer()
                Button("Refresh apps", action: refresh)
                Button(observer.isPaused ? "Resume" : "Pause", action: observer.togglePause)
            }
            CaptureHealthView(observer: observer)
            PermissionControls(observer: observer)
            Text("Choose once for each app. Conre then runs quietly in the background.").font(.subheadline)
            Text("App activity saves app/window history. Detailed text adds exposed content. Visual fallback adds temporary window-only OCR when text access fails; images are not saved. Visual text may include sensitive information.")
                .font(.caption).foregroundStyle(.secondary)
            List(apps) { app in
                HStack {
                    VStack(alignment: .leading) {
                        Text(app.name).font(.headline)
                        if let latest = observer.context.snapshots.last(where: { $0.bundleID == app.id }) {
                            Text(latest.health.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Picker("Capture for \(app.name)", selection: Binding(get: { observer.captureMode(for: app.id) }, set: { observer.setCaptureMode(app.id, mode: $0) })) {
                        ForEach(AppCaptureMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 185)
                }.padding(.vertical, 5)
            }
            if let warning = observer.context.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
        }.padding(16).onAppear(perform: refresh)
    }
    private func refresh() {
        var names: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier { names[id] = app.localizedName ?? id }
        }
        for id in observer.approvedIDs where names[id] == nil {
            names[id] = observer.log.events.last(where: { $0.bundleID == id })?.applicationName ?? id
        }
        apps = names.map { AppChoice(id: $0.key, name: $0.value) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct PermissionControls: View {
    let observer: ActivityObserver
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !observer.detailedIDs.isEmpty {
                HStack {
                    Label(observer.accessibilityGranted ? "Text access ready" : "Accessibility permission needed", systemImage: observer.accessibilityGranted ? "checkmark.circle" : "lock")
                    Spacer()
                    if !observer.accessibilityGranted { Button("Allow text access…", action: observer.requestWindowPermission) }
                }
            }
            if !observer.visualIDs.isEmpty {
                HStack {
                    Label(observer.visualPermissionGranted ? "Visual fallback permission ready" : "Screen Recording permission needed", systemImage: observer.visualPermissionGranted ? "checkmark.circle" : "lock")
                    Spacer()
                    if !observer.visualPermissionGranted { Button("Allow window capture…", action: observer.requestVisualPermission) }
                }
                if !observer.visualPermissionGranted { Text("Enable Conre in Privacy & Security → Screen Recording. macOS may require a relaunch.").font(.caption2).foregroundStyle(.secondary) }
            }
        }.font(.caption)
    }
}
