import SwiftUI

struct ContextInspectorView: View {
    let observer: ActivityObserver
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Detailed context").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("Accessibility text is tried first. Optional window-only visual fallback uses a temporary image and on-device OCR when no text is available. Images are not saved; extracted text stays local. No audio, AI, or uploads. Visual capture may include sensitive information and cannot reliably exclude individual fields.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(orderedApps, id: \.self) { id in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(appName(id), isOn: Binding(get: { observer.detailedIDs.contains(id) },
                                                             set: { observer.enableDetailedContext(id, enabled: $0) }))
                            if observer.detailedIDs.contains(id) {
                                if observer.contextFailures.contains(id) || observer.settingsAppID == id {
                                    Label("No usable context gathered", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(.red)
                                }
                                Toggle("Window-only visual fallback", isOn: Binding(get: { observer.visualIDs.contains(id) },
                                                                                   set: { observer.enableVisualFallback(id, enabled: $0) }))
                                    .font(.caption)
                                if observer.visualIDs.contains(id) {
                                    Text("Only this app's focused window, when Accessibility returns no text. Switch back to the app after enabling.")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                    if observer.approvedIDs.isEmpty { Text("Approve apps in App awareness first.").foregroundStyle(.secondary) }
                }
            }.frame(maxHeight: 200)
            if !observer.visualIDs.isEmpty && !observer.visualPermissionGranted {
                Button("Allow Screen Recording for window-only capture…", action: observer.requestVisualPermission)
                Text("macOS grants screen-recording access broadly; Conre restricts capture to the approved foreground window. Enable Conre in Privacy & Security → Screen Recording if prompted. A relaunch may be required.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(observer.contextStatus).font(.caption)
            Text("Checks adapt from 12 to 60 seconds when content stays similar. Accessibility coverage varies; this is evidence of exposed content, not a record of confirmed actions.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Saved captures · \(observer.context.snapshots.count)").font(.headline)
                Spacer()
                Button("Delete context", role: .destructive, action: observer.clearContext)
            }
            Text("\(observer.context.consolidatedSamples) repeated samples consolidated this run. Similar OCR views keep the latest wording; small OCR-only changes may not become separate events.")
                .font(.caption).foregroundStyle(.secondary)
            if let warning = observer.context.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
            List(observer.context.snapshots.reversed()) { snapshot in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source: \(snapshot.source == "windowOCR" ? "Window-only OCR" : "Accessibility") · \(snapshot.status)").font(.caption).foregroundStyle(.secondary)
                        Text(snapshot.text.isEmpty ? "No text captured." : snapshot.text)
                            .font(.system(.caption, design: .monospaced))
                    }.textSelection(.enabled)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.windowTitle ?? snapshot.applicationName).font(.headline)
                        Text("\(snapshot.applicationName) · \(snapshot.status)").font(.caption).lineLimit(2)
                        Text(snapshot.timestamp, format: .dateTime.month().day().hour().minute().second())
                            .font(.caption).foregroundStyle(.secondary)
                        if let last = snapshot.lastSeenAt {
                            Text("Last seen \(last.formatted(date: .omitted, time: .standard)) · \(snapshot.sampleCount ?? 1) samples")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.padding(20).frame(minWidth: 600, minHeight: 620)
    }
    private var orderedApps: [String] {
        let ids = observer.approvedIDs.sorted()
        guard let selected = observer.settingsAppID, ids.contains(selected) else { return ids }
        return [selected] + ids.filter { $0 != selected }
    }
    private func appName(_ id: String) -> String {
        observer.log.events.last(where: { $0.bundleID == id })?.applicationName ?? id
    }
}
