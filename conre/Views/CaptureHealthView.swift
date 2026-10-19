import SwiftUI

struct CaptureHealthView: View {
    let observer: ActivityObserver
    var body: some View {
        let health = observer.captureHealth
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: health.symbol).foregroundStyle(color(health))
            VStack(alignment: .leading, spacing: 4) {
                Text(health.rawValue).font(.subheadline.bold())
                if let result = observer.latestCapture {
                    Text("Latest result: \(result.applicationName) · \(result.source == "windowOCR" ? "Window OCR" : "Text access")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let useful = observer.lastUsefulCapture {
                    HStack(spacing: 3) {
                        Text("Last useful text:")
                        Text(useful.latestDate, style: .relative)
                        Text("ago · \(useful.applicationName)")
                    }.font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if health.needsAttention {
                Button("Review") { observer.navigateToApps = true }
            }
        }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
    private func color(_ health: CaptureHealth) -> Color {
        switch health {
        case .captured: .green
        case .partial: .orange
        case .permission, .unavailable: .red
        default: .secondary
        }
    }
}
