import SwiftUI

struct TimelineView: View {
    let memory: WorkingMemoryStore
    let observer: ActivityObserver

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("conre.").font(.system(size: 26, weight: .semibold, design: .rounded))
                Spacer()
                Button(action: observer.togglePause) {
                    Label(observer.isPaused ? "Resume" : "Pause", systemImage: observer.isPaused ? "play.fill" : "pause.fill")
                }
                .help("Pause or resume approved-app observation.")
            }
            .padding(20)

            VStack(alignment: .leading, spacing: 7) {
                Text("CURRENT THREAD · SYNDEO").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(memory.activeThread?.title ?? "No active thread").font(.headline)
                Text("Sample workflow · All activities below are mock data")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(memory.chronologicalEvents()) { event in
                            HStack(alignment: .top, spacing: 14) {
                                Text(event.timestamp, format: .dateTime.hour().minute())
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(width: 58, alignment: .trailing)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(event.description).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                                    Text("\(event.applicationName) · \(event.source == .mock ? "Mock" : event.source == .observed ? "Observed" : "AI-generated")")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Divider().padding(.top, 10)
                                }
                            }
                            .padding(.top, 16)
                            .id(event.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    if let id = memory.chronologicalEvents().last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label(observer.status,
                      systemImage: observer.isPaused ? "pause.circle" : "circle.dotted")
                Text("Raw app activity appears separately in App awareness.")
                if let message = memory.persistenceMessage { Text(message).foregroundStyle(.orange) }
            }
            .font(.caption).foregroundStyle(.secondary).padding(16)
        }
        .frame(minWidth: 360, idealWidth: 420, minHeight: 420, idealHeight: 590)
        .background(.background)
    }
}
