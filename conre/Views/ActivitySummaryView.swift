import SwiftUI

struct SummaryActionView: View {
    let observer: ActivityObserver
    let controller: SummaryController
    @State private var minutes = 60
    @State private var preview: SummaryInput?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Period", selection: $minutes) {
                    Text("Last 15 minutes").tag(15)
                    Text("Last hour").tag(60)
                    Text("Last 4 hours").tag(240)
                }.labelsHidden().frame(maxWidth: 160)
                Spacer()
                if controller.isGenerating {
                    ProgressView().controlSize(.small)
                    Button("Cancel", action: controller.cancel)
                } else {
                    Button("Summarize recent activity", systemImage: "sparkles") {
                        let now = Date()
                        preview = SummaryInput.build(observer.context.snapshots, since: now.addingTimeInterval(-Double(minutes * 60)), until: now)
                    }
                }
            }
            Text("OpenAI · Review selected text before sending. API usage is billed to your account.").font(.caption2).foregroundStyle(.secondary)
            if let error = controller.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }
        .sheet(item: $preview) { input in
            SummaryPreviewView(input: input) { key in
                controller.generate(input, using: OpenAIActivitySummarizer(key: key)); preview = nil
            }
        }
    }
}

extension SummaryInput: Identifiable {
    var id: Date { end }
}

private struct SummaryPreviewView: View {
    let input: SummaryInput
    let generate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var savedCredential: String?
    @State private var keychainBusy = false
    private var hasKey: Bool { savedCredential != nil }
    @State private var keyMessage: String?
    @State private var manageKey = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review activity context").font(.title2.bold())
            Text("Clicking Send to OpenAI sends only the text below, app names, window titles, timestamps, and evidence IDs to api.openai.com using GPT-4.1 mini. No images are uploaded. API charges apply. The resulting summary and supporting excerpts are saved locally until replaced or cleared.").font(.caption).foregroundStyle(.secondary)
            Text("\(input.start.formatted(date: .omitted, time: .shortened))–\(input.end.formatted(date: .omitted, time: .shortened)) · \(input.evidence.count) observations").font(.caption)
            if input.evidence.isEmpty {
                ContentUnavailableView("Not enough context", systemImage: "text.viewfinder", description: Text("Choose a longer period or enable Detailed text in Apps."))
            } else {
                List(input.evidence) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.app).font(.headline)
                        Text(item.timestamp, format: .dateTime.hour().minute()).font(.caption)
                        if let window = item.window { Text(window).font(.caption) }
                        Text(item.source).font(.caption2).foregroundStyle(.secondary)
                        Text(item.text).font(.caption).textSelection(.enabled)
                    }.padding(.vertical, 5)
                }
            }
            DisclosureGroup(hasKey ? "OpenAI API key saved · Manage" : "Add your OpenAI API key", isExpanded: $manageKey) {
                VStack(alignment: .leading, spacing: 6) {
                    SecureField("OpenAI API key", text: $key).disabled(keychainBusy)
                    HStack {
                        Button("Save to Keychain") {
                            Task {
                                keychainBusy = true
                                defer { keychainBusy = false }
                                do {
                                    savedCredential = try await SummaryKeychainAccess.shared.saveAndVerify(key)
                                    key = ""; keyMessage = "Saved and verified in Keychain."
                                } catch { savedCredential = nil; keyMessage = error.localizedDescription }
                            }
                        }.disabled(key.isEmpty || keychainBusy)
                        if hasKey {
                            Button("Remove key", role: .destructive) {
                                Task {
                                    keychainBusy = true
                                    defer { keychainBusy = false }
                                    do { try await SummaryKeychainAccess.shared.remove(); savedCredential = nil; key = ""; keyMessage = "Key removed." }
                                    catch { keyMessage = error.localizedDescription }
                                }
                            }.disabled(keychainBusy)
                        }
                    }
                    if !hasKey {
                        Button("Retry Keychain access") { Task { await loadSavedKey() } }.disabled(keychainBusy)
                    }
                    if keychainBusy { ProgressView("Checking Keychain…").controlSize(.small) }

                    Text("Your key is stored in Keychain and used for manual and enabled automatic summaries. It is never stored in history or preferences.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let keyMessage { Text(keyMessage).font(.caption).foregroundStyle(.secondary) }
            Text("Requests use store: false; OpenAI data policies still apply. Only a bounded selection of recent text changes is included, so activity may be incomplete.").font(.caption2).foregroundStyle(.secondary)
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Send to OpenAI & summarize") {
                if let savedCredential { generate(savedCredential) }
            }
                    .buttonStyle(.borderedProminent).disabled(input.evidence.isEmpty || !hasKey || keychainBusy) }
        }.padding(20).frame(minWidth: 500, idealWidth: 580, minHeight: 420, idealHeight: 700)
        .task { await loadSavedKey() }
        .onDisappear { key = ""; savedCredential = nil }
    }
    private func loadSavedKey() async {
        keychainBusy = true
        defer { keychainBusy = false }
        do {
            let value = try await SummaryKeychainAccess.shared.read()
            guard !Task.isCancelled else { return }
            savedCredential = value; manageKey = value == nil; keyMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            savedCredential = nil; manageKey = true; keyMessage = error.localizedDescription
        }
    }
}

struct ActivitySummaryTreeView: View {
    let controller: SummaryController
    var body: some View {
        if let result = controller.result {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.sentence).font(.headline).textSelection(.enabled)
                    Text("Activity tree · AI interpretation of observed text").font(.caption).foregroundStyle(.secondary)
                    Text("\(result.input.start.formatted(date: .abbreviated, time: .shortened))–\(result.input.end.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                    ForEach(result.roots) { node in ActivityTreeBranch(node: node) }
                    Divider()
                    Text("Steps may be incomplete or mistaken. Expand a step to see its evidence. This tree updates only when you generate it again; clearing captured context does not remove this saved summary.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Clear saved summary", role: .destructive, action: controller.clear)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
        } else {
            ContentUnavailableView("Pick up your train of thought", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Summarize recent activity to create a short overview and an expandable tree of what you were working on."))
        }
    }
}

private struct ActivityTreeBranch: View {
    let node: ActivityTreeNode
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(node.children) { child in
                    // Type erasure breaks the recursive SwiftUI opaque return type.
                    AnyView(ActivityTreeBranch(node: child))
                }
                DisclosureGroup("Supporting observations · \(node.evidence.count)") {
                    ForEach(node.evidence) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.app) · \(item.timestamp.formatted(date: .omitted, time: .shortened))").font(.caption.bold())
                            if let window = item.window { Text(window).font(.caption2) }
                            Text(item.source).font(.caption2).foregroundStyle(.secondary)
                            Text(item.text).font(.caption).textSelection(.enabled)
                        }.padding(.vertical, 4)
                    }
                }.font(.caption)
            }.padding(.leading, 8).padding(.vertical, 5)
        } label: { Label(node.title, systemImage: node.children.isEmpty ? "doc.text" : "folder").font(.subheadline) }
    }
}
