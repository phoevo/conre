import SwiftUI

struct ContextInspectorView: View {
    let observer: ActivityObserver
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Captured context").font(.title2.bold())
                Spacer()
                Button("Manage apps") { observer.navigateToApps = true; dismiss() }
                Button("Done") { dismiss() }
            }
            CaptureHealthView(observer: observer)
            if let id = observer.settingsAppID, observer.contextFailures.contains(id), observer.captureMode(for: id) == .text {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Text access isn't providing context for \(appName(id)).").font(.subheadline)
                    Text("Optional fallback reads only its focused window with local OCR. Temporary images are discarded; extracted text stays local and may contain sensitive information.").font(.caption).foregroundStyle(.secondary)
                    Button("Enable window-only visual fallback") { observer.setCaptureMode(id, mode: .visual) }
                }
            }
            PermissionControls(observer: observer)
            HStack {
                Text("Saved captures · \(observer.context.snapshots.count)").font(.headline)
                Spacer()
                Button("Delete context", role: .destructive, action: observer.clearContext)
            }
            Text("Partial observations, not confirmed actions. OCR can misread code and text. Images are not saved or uploaded.").font(.caption).foregroundStyle(.secondary)
            if let warning = observer.context.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
            List(observer.context.snapshots.sorted { $0.latestDate > $1.latestDate }) { snapshot in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.text.isEmpty ? "No usable text in this attempt." : snapshot.text)
                            .font(.system(.caption, design: .monospaced))
                        DisclosureGroup("Technical diagnostics") { Text(snapshot.status).font(.caption2).foregroundStyle(.secondary) }
                    }.textSelection(.enabled)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.windowTitle ?? snapshot.applicationName).font(.headline)
                        Text("\(snapshot.applicationName) · \(snapshot.health.rawValue) · \(snapshot.source == "windowOCR" ? "Window OCR" : "Text access")").font(.caption)
                        Text(snapshot.latestDate, format: .dateTime.month().day().hour().minute().second()).font(.caption2).foregroundStyle(.secondary)
                        if (snapshot.sampleCount ?? 1) > 1 { Text("\(snapshot.sampleCount ?? 1) similar samples combined").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }.padding(20).frame(minWidth: 600, minHeight: 620)
    }
    private func appName(_ id: String) -> String { observer.log.events.last(where: { $0.bundleID == id })?.applicationName ?? id }
}
