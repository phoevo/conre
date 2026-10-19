import SwiftUI
import AppKit

@MainActor
final class FloatingStatusController {
    private var panel: NSPanel?
    private var screenToken: NSObjectProtocol?
    private var observer: ActivityObserver?
    private var appearance: StatusAppearance?
    private var assistant: WorkAssistant?
    private var openApp: (() -> Void)?
    func show(observer: ActivityObserver, appearance: StatusAppearance, assistant: WorkAssistant, openApp: @escaping () -> Void) {
        guard panel == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 250, height: 32),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false
        self.assistant = assistant
        assistant.onRecapChange = { [weak self] in self?.position() }
        self.observer = observer
        self.appearance = appearance
        self.openApp = openApp
        self.panel = panel
        position()
        panel.orderFrontRegardless()
        screenToken = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.position() }
        }
    }
    private func position() {
        guard let panel, let observer, let appearance, let assistant, let openApp,
              let screen = NSScreen.screens.first(where: { $0.auxiliaryTopRightArea != nil }) ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let compactHeight: CGFloat
        let compactOrigin: NSPoint
        if let area = screen.auxiliaryTopRightArea {
            compactHeight = min(28, area.height - 4)
            compactOrigin = NSPoint(x: min(area.minX + 8, area.maxX - 250 - 8),
                                    y: area.midY - compactHeight / 2)
        } else {
            compactHeight = min(24, max(18, NSStatusBar.system.thickness - 4))
            compactOrigin = NSPoint(x: frame.maxX - 250 - 8,
                                    y: frame.maxY - (NSStatusBar.system.thickness + compactHeight) / 2)
        }
        let expanded = assistant.recap != nil
        // Keep the same top edge and notch-side edge throughout expansion.
        // The existing pill grows outward and down instead of moving below the menu bar.
        let notchSide = screen.auxiliaryTopRightArea != nil
        let width: CGFloat = expanded ? min(420, notchSide ? frame.maxX - compactOrigin.x - 8 : frame.width - 16) : 250
        let height: CGFloat
        if expanded {
            let textHeight = ((assistant.recap?.text ?? "") as NSString).boundingRect(
                with: NSSize(width: width - 48, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: NSFont.systemFont(ofSize: 12)]).height
            height = min(180, max(124, ceil(textHeight) + 98))
        } else { height = compactHeight }
        let origin = NSPoint(x: notchSide ? compactOrigin.x : compactOrigin.x + 250 - width,
                             y: compactOrigin.y + compactHeight - height)
        panel.contentView = NSHostingView(rootView: Group {
            if let recap = assistant.recap {
                ReturnRecapView(recap: recap, appearance: appearance, dismiss: assistant.dismissRecap) {
                    assistant.dismissRecap(); openApp()
                }
            } else {
                FloatingStatus(observer: observer, appearance: appearance, assistant: assistant, height: height, openApp: openApp)
            }
        })
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true,
                       animate: panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

private struct FloatingStatus: View {
    let observer: ActivityObserver
    let appearance: StatusAppearance
    let assistant: WorkAssistant
    let height: CGFloat
    let openApp: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button {
            if observer.hasContextWarning { observer.openContextSettings() }
            openApp()
        } label: {
            HStack(spacing: 8) {
                if assistant.summary.isGenerating || assistant.preparing {
                    ProgressView().controlSize(.mini).tint(appearance.iconColor).frame(width: 14, height: 14)
                } else if observer.hasContextWarning {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if observer.statusKind == .waiting && !reduceMotion {
                    ProgressView().controlSize(.mini).tint(appearance.iconColor).frame(width: 14, height: 14)
                } else {
                Image(systemName: observer.statusKind.symbol)
                    .symbolEffect(.wiggle, options: .repeating, isActive: !reduceMotion && observer.statusKind == .recording)
                    .symbolEffect(.bounce, value: reduceMotion ? "" : observer.statusKind.rawValue)
                    .foregroundStyle(appearance.iconColor)
                }
                Text(assistant.summary.isGenerating || assistant.preparing ? "Connecting your recent work…" : observer.hasContextWarning ? observer.captureHealth.rawValue : observer.status).foregroundStyle(observer.hasContextWarning ? .red : appearance.textColor).lineLimit(1).font(.system(size: 11, weight: .medium))
            }.padding(.horizontal, 12).frame(width: 250, height: height)
                .modifier(StatusPillSurface(appearance: appearance))
                .contentShape(Capsule())
        }.buttonStyle(.plain).help(observer.hasContextWarning ? "Context unavailable. Open per-app visual fallback settings." : "Open Conre")
            .accessibilityLabel(observer.hasContextWarning ? "Context not gathered. Click to configure window-only visual capture." : "\(observer.status). Click to open Conre.")
    }
}

struct ReturnRecapView: View {
    let recap: WorkRecap
    let appearance: StatusAppearance
    let dismiss: () -> Void
    let openApp: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.uturn.backward").foregroundStyle(appearance.recapHeadingColor)
                Text("Where you left off").font(.caption.weight(.semibold)).foregroundStyle(appearance.recapHeadingColor)
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark").font(.caption2).foregroundStyle(appearance.recapHeadingColor) }.buttonStyle(.plain).help("Dismiss recap")
            }
            Button(action: openApp) {
                Text(recap.text).font(.system(size: 12)).lineSpacing(2).multilineTextAlignment(.leading)
                    .foregroundStyle(appearance.recapTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(5)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(appearance.recapTextBackgroundColor))
            }.buttonStyle(.plain).help("Open your activity tree")
            Text("\(recap.isAI ? "Last summary" : "Last observed window") · \(recap.through.formatted(date: Calendar.current.isDateInToday(recap.through) ? .omitted : .abbreviated, time: .shortened))")
                .font(.system(size: 10)).foregroundStyle(appearance.recapTimeColor)
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18).fill(appearance.recapBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(appearance.recapRingColor, lineWidth: 1))
    }
}
