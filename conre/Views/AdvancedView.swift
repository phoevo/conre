import SwiftUI

struct AdvancedView: View {
    let observer: ActivityObserver
    let memory: WorkingMemoryStore
    let assistant: WorkAssistant
    @State private var showRaw = false
    @State private var showSample = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Advanced").font(.title2.bold())
                Text("Capture diagnostics and developer tools. Real activity is in Recent work.").font(.caption).foregroundStyle(.secondary)
                GroupBox("AI summaries") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Summarize automatically", isOn: Binding(get: { assistant.automaticEnabled }, set: { assistant.automaticEnabled = $0 }))
                        Text("Selected captured text is sent to OpenAI using your saved key when enough new information accumulates. API charges apply. At least 2 minutes between automatic requests; at most 12 per hour. Errors back off for 10 minutes. Pause observations to pause automatic requests.").font(.caption).foregroundStyle(.secondary)
                        Text(assistant.automaticStatus).font(.caption)
                        if let error = assistant.automaticError { Text(error).font(.caption).foregroundStyle(.orange) }
                        SummaryActionView(observer: observer, controller: assistant.summary)
                        if assistant.summary.result != nil { Button("Clear saved summary", role: .destructive, action: assistant.summary.clear) }
                    }.padding(6)
                }
                CaptureHealthView(observer: observer)
                GroupBox("Background work · This run") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Completed attempts", value: "\(observer.performance.attempts)")
                        LabeledContent("Average capture time", value: String(format: "%.2f s", observer.performance.averageSeconds))
                        LabeledContent("Longest capture", value: String(format: "%.2f s", observer.performance.longestCaptureSeconds))
                        LabeledContent("OCR runs / reused results", value: "\(observer.performance.ocrRuns) / \(observer.performance.reusedOCR)")
                        LabeledContent("History writes", value: "\(observer.performance.diskWrites)")
                        LabeledContent("History bytes written", value: ByteCountFormatter.string(fromByteCount: Int64(observer.performance.writtenBytes), countStyle: .file))
                        LabeledContent("Repeat samples consolidated", value: "\(observer.context.consolidatedSamples)")
                        Text("Capture time is elapsed time, not CPU time. Counts start at launch and exclude cancelled attempts and OS-internal writes.").font(.caption2).foregroundStyle(.secondary)
                    }.font(.caption).padding(6)
                }
                Button("Inspect saved context…") { observer.contextSettingsPresented = true }
                DisclosureGroup("Raw app/window observations", isExpanded: $showRaw) {
                    if showRaw {
                        HStack { Text("\(observer.log.events.count) records · Showing newest 100").font(.caption); Spacer(); Button("Clear app history", role: .destructive) { observer.log.clear() } }
                        ForEach(observer.log.events.suffix(100).reversed()) { event in
                            VStack(alignment: .leading) {
                                Text("\(event.applicationName) · \(event.windowTitle ?? event.windowStatus)")
                                Text(event.timestamp, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
                            }.font(.caption).textSelection(.enabled)
                            Divider()
                        }
                    }
                }
                DisclosureGroup("Sample timeline · Mock data", isExpanded: $showSample) {
                    if showSample {
                        Text("This is the original Syndeo demonstration. It is not generated from your activity.").font(.caption).foregroundStyle(.orange)
                        TimelineView(memory: memory, observer: observer).frame(height: 550)
                    }
                }
                if let message = observer.log.warning { Text(message).font(.caption).foregroundStyle(.orange) }
            }.padding(16)
        }
    }
}
