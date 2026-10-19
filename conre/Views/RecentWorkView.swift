import SwiftUI

struct RecentWorkView: View {
    let observer: ActivityObserver
    let assistant: WorkAssistant
    @State private var showTools = false
    private var summary: SummaryController { assistant.summary }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Recent work").font(.title3.weight(.semibold))
                Spacer()
                if summary.isGenerating || assistant.preparing { ProgressView().controlSize(.mini).help("Updating your activity tree") }
                Button(observer.isPaused ? "Resume" : "Pause", action: observer.togglePause).buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                Button { showTools = true } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }.buttonStyle(.plain).help("Summary options and API key")
            }
            if let result = summary.result {
                Text(result.sentence).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let result = summary.result {
                        ForEach(result.roots) { node in WorkTreeBranch(node: node, initiallyExpanded: true) }
                    }
                    let recent = ContextChange.build(observer.context.snapshots).filter { $0.snapshot.timestamp > (summary.result?.input.end ?? .distantPast) }.prefix(8)
                    if !recent.isEmpty {
                        if summary.result != nil { Text("Since the last update").font(.caption).foregroundStyle(.secondary).padding(.top, 6) }
                        ForEach(Array(recent.reversed())) { change in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(change.snapshot.latestDate, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary)
                                    ForEach(Array(change.added.prefix(4).enumerated()), id: \.offset) { _, text in
                                        Text(String(text.prefix(300))).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                }.padding(.leading, 20).padding(.vertical, 6)
                            } label: {
                                Label(change.snapshot.windowTitle ?? change.snapshot.applicationName, systemImage: "text.alignleft").font(.subheadline).lineLimit(2)
                            }
                        }
                    }
                    if summary.result == nil && recent.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your work, connected.").font(.headline)
                            Text("Use your approved apps normally. New context will appear here and form an activity tree as you work.").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.top, 32)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }
            HStack(spacing: 5) {
                Circle().fill(observer.isPaused ? Color.secondary : Color.accentColor).frame(width: 4, height: 4)
                Text(observer.isPaused ? "Paused" : assistant.automaticStatus).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if assistant.automaticError != nil || summary.error != nil { Button("Review update issue") { showTools = true }.font(.caption2) }
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showTools) {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("Summary options").font(.headline); Spacer(); Button("Done") { showTools = false } }
                Toggle("Summarize automatically", isOn: Binding(get: { assistant.automaticEnabled }, set: { assistant.automaticEnabled = $0 }))
                Text("Automatic updates send selected activity text to OpenAI with your saved key. API charges apply. More options are in Advanced.").font(.caption).foregroundStyle(.secondary)
                if let error = assistant.automaticError { Text(error).font(.caption).foregroundStyle(.orange) }
                SummaryActionView(observer: observer, controller: summary)
            }.padding(24).frame(width: 500)
        }
    }
}

private struct WorkTreeBranch: View {
    let node: ActivityTreeNode
    @State private var expanded: Bool
    init(node: ActivityTreeNode, initiallyExpanded: Bool = false) {
        self.node = node; _expanded = State(initialValue: initiallyExpanded)
    }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(node.children) { child in AnyView(WorkTreeBranch(node: child)) }
                DisclosureGroup("Observed context") {
                    ForEach(node.evidence) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(item.app) · \(item.timestamp.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                            Text(item.text).font(.caption).textSelection(.enabled)
                        }.padding(.vertical, 5)
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(.leading, 16).padding(.vertical, 8)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: node.children.isEmpty ? "circle" : "point.3.connected.trianglepath.dotted").font(.caption).foregroundStyle(.tertiary)
                Text(node.title).font(.subheadline.weight(node.children.isEmpty ? .regular : .medium))
            }
        }
    }
}
