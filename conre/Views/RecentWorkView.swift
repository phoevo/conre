import SwiftUI

struct RecentWorkView: View {
    let observer: ActivityObserver
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What was I doing?").font(.title2.bold())
                Spacer()
                Button(observer.isPaused ? "Resume" : "Pause", action: observer.togglePause)
            }
            Text("Your recent apps and windows, collected automatically while Conre runs.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Times are approximate foreground time, not proof of attention. Older records may have no duration.")
                .font(.caption).foregroundStyle(.secondary)
            if let warning = observer.log.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
            let sessions = ActivitySession.grouped(observer.log.events)
            if sessions.isEmpty {
                ContentUnavailableView("No recent work yet", systemImage: "clock", description: Text("Approve apps in App awareness, then use them to start your activity history."))
            } else {
                List(sessions.reversed()) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(session.applicationName, systemImage: "app")
                                .font(.headline)
                            Spacer()
                            Text(duration(session.knownDuration)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text(session.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            if let end = session.endedAt {
                                Text("–")
                                Text(end, format: .dateTime.hour().minute())
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                        if let intent = session.intentNote { Label(intent, systemImage: "pin").font(.subheadline) }
                        ForEach(Array(session.titles.enumerated()), id: \.offset) { _, title in
                            Label(title, systemImage: "chevron.right").font(.caption)
                        }
                    }.padding(.vertical, 5).textSelection(.enabled)
                }
            }
        }.padding(16)
    }
    private func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "Duration unknown" }
        let value = Int(seconds)
        if value < 60 { return "\(value)s" }
        if value < 3600 { return "\(value / 60)m \(value % 60)s" }
        return "\(value / 3600)h \((value % 3600) / 60)m"
    }
}
