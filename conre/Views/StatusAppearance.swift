import SwiftUI
import AppKit
import Observation

@MainActor @Observable
final class StatusAppearance {
    var iconColor: Color { didSet { save(iconColor, key: "statusIconColor") } }
    var textColor: Color { didSet { save(textColor, key: "statusTextColor") } }
    var ringColor: Color { didSet { save(ringColor, key: "statusRingColor") } }
    var backgroundColor: Color { didSet { save(backgroundColor, key: "statusBackgroundColor") } }
    var recapHeadingColor: Color { didSet { save(recapHeadingColor, key: "recapHeadingColor") } }
    var recapTextColor: Color { didSet { save(recapTextColor, key: "recapTextColor") } }
    var recapTimeColor: Color { didSet { save(recapTimeColor, key: "recapTimeColor") } }
    var recapBackgroundColor: Color { didSet { save(recapBackgroundColor, key: "recapBackgroundColor") } }
    var recapTextBackgroundColor: Color { didSet { save(recapTextBackgroundColor, key: "recapTextBackgroundColor") } }
    var recapRingColor: Color { didSet { save(recapRingColor, key: "recapRingColor") } }
    init() {
        recapHeadingColor = Self.load("recapHeadingColor", fallback: .green)
        recapTextColor = Self.load("recapTextColor", fallback: .white)
        recapTimeColor = Self.load("recapTimeColor", fallback: .green)
        recapBackgroundColor = Self.load("recapBackgroundColor", fallback: Color(.sRGB, white: 0.09, opacity: 0.97))
        recapTextBackgroundColor = Self.load("recapTextBackgroundColor", fallback: .white.opacity(0.06))
        recapRingColor = Self.load("recapRingColor", fallback: .white.opacity(0.25))
        iconColor = Self.load("statusIconColor")
        textColor = Self.load("statusTextColor")
        ringColor = Self.load("statusRingColor")
        backgroundColor = Self.load("statusBackgroundColor", fallback: .black.opacity(0.85))
    }
    private static func load(_ key: String, fallback: Color = .white) -> Color {
        guard let values = UserDefaults.standard.array(forKey: key) as? [Double], (values.count == 3 || values.count == 4) else { return fallback }
        return Color(.sRGB, red: values[0], green: values[1], blue: values[2], opacity: values.count == 4 ? values[3] : 1)
    }
    private func save(_ color: Color, key: String) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent), Double(rgb.alphaComponent)], forKey: key)
    }
}

struct StatusAppearanceView: View {
    @Bindable var appearance: StatusAppearance
    var body: some View {
        Form {
            Section("Floating status") {
                ColorPicker("Icon color", selection: $appearance.iconColor, supportsOpacity: false)
                ColorPicker("Text color", selection: $appearance.textColor, supportsOpacity: false)
                ColorPicker("Ring color", selection: $appearance.ringColor, supportsOpacity: true)
                ColorPicker("Background color", selection: $appearance.backgroundColor, supportsOpacity: true)
                HStack(spacing: 8) {
                    Image(systemName: "pencil.line").foregroundStyle(appearance.iconColor)
                    Text("Recording app activity").foregroundStyle(appearance.textColor)
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12).frame(width: 250, height: 28)
                .modifier(StatusPillSurface(appearance: appearance))
                Text("Colors update immediately and are saved for next time. Click the floating status to open Conre; pause or resume in Recent work.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset colors") {
                    appearance.iconColor = .white; appearance.textColor = .white
                    appearance.ringColor = .white; appearance.backgroundColor = .black.opacity(0.85)
                }
            }
            Section("Return reminder") {
                ColorPicker("Heading and icon", selection: $appearance.recapHeadingColor, supportsOpacity: false)
                ColorPicker("Summary text", selection: $appearance.recapTextColor, supportsOpacity: false)
                ColorPicker("Timestamp", selection: $appearance.recapTimeColor, supportsOpacity: false)
                ColorPicker("Summary background", selection: $appearance.recapTextBackgroundColor, supportsOpacity: true)
                ColorPicker("Reminder background", selection: $appearance.recapBackgroundColor, supportsOpacity: true)
                ColorPicker("Reminder ring", selection: $appearance.recapRingColor, supportsOpacity: true)
                ReturnRecapView(recap: WorkRecap(text: "You were refining button styles and adjusting theme colors.", through: Date(), isAI: true), appearance: appearance, dismiss: {}, openApp: {})
                    .frame(height: 145).allowsHitTesting(false).accessibilityLabel("Reminder color preview")
                Text("Reminder colors are independent of the compact status pill and are saved automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset reminder colors") {
                    appearance.recapHeadingColor = .green
                    appearance.recapTextColor = .white
                    appearance.recapTimeColor = .green
                    appearance.recapBackgroundColor = Color(.sRGB, white: 0.09, opacity: 0.97)
                    appearance.recapTextBackgroundColor = .white.opacity(0.06)
                    appearance.recapRingColor = .white.opacity(0.25)
                }
            }
        }.formStyle(.grouped)
    }
}


struct StatusPillSurface: ViewModifier {
    let appearance: StatusAppearance
    func body(content: Content) -> some View {
        content
            .background { Capsule().fill(appearance.backgroundColor) }
            .overlay { Capsule().strokeBorder(appearance.ringColor, lineWidth: 1) }
    }
}
