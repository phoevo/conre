import SwiftUI
import AppKit

@MainActor
final class FloatingStatusController {
    private var panel: NSPanel?
    private var screenToken: NSObjectProtocol?
    private var observer: ActivityObserver?
    private var appearance: StatusAppearance?
    private var openApp: (() -> Void)?
    func show(observer: ActivityObserver, appearance: StatusAppearance, openApp: @escaping () -> Void) {
        guard panel == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 250, height: 32),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false
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
        guard let panel, let observer, let appearance, let openApp,
              let screen = NSScreen.screens.first(where: { $0.auxiliaryTopRightArea != nil }) ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let width: CGFloat = 250
        let height: CGFloat
        let origin: NSPoint
        if let area = screen.auxiliaryTopRightArea {
            // auxiliaryTopRightArea is the usable menu-bar strip beside the notch.
            // Center inside that strip instead of subtracting its height from the screen.
            height = min(28, area.height - 4)
            origin = NSPoint(x: min(area.minX + 8, area.maxX - width - 8),
                             y: area.midY - height / 2)
        } else {
            // Flat displays: stay in the menu-bar strip, above application windows.
            height = min(24, max(18, NSStatusBar.system.thickness - 4))
            origin = NSPoint(x: frame.maxX - width - 8,
                             y: frame.maxY - (NSStatusBar.system.thickness + height) / 2)
        }
        panel.contentView = NSHostingView(rootView: FloatingStatus(observer: observer, appearance: appearance, height: height, openApp: openApp))
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }
}

private struct FloatingStatus: View {
    let observer: ActivityObserver
    let appearance: StatusAppearance
    let height: CGFloat
    let openApp: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button {
            if observer.hasContextWarning { observer.openContextSettings() }
            openApp()
        } label: {
            HStack(spacing: 8) {
                if observer.hasContextWarning {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if observer.statusKind == .waiting && !reduceMotion {
                    ProgressView().controlSize(.mini).tint(appearance.iconColor).frame(width: 14, height: 14)
                } else {
                Image(systemName: observer.statusKind.symbol)
                    .symbolEffect(.wiggle, options: .repeating, isActive: !reduceMotion && observer.statusKind == .recording)
                    .symbolEffect(.bounce, value: reduceMotion ? "" : observer.statusKind.rawValue)
                    .foregroundStyle(appearance.iconColor)
                }
                Text(observer.hasContextWarning ? "Context not gathered" : observer.status).foregroundStyle(observer.hasContextWarning ? .red : appearance.textColor).lineLimit(1).font(.system(size: 11, weight: .medium))
            }.padding(.horizontal, 12).frame(width: 250, height: height)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(observer.hasContextWarning ? "Context unavailable. Open per-app visual fallback settings." : "Open Conre")
            .accessibilityLabel(observer.hasContextWarning ? "Context not gathered. Click to configure window-only visual capture." : "\(observer.status). Click to open Conre.")
    }
}
