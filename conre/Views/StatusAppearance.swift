import SwiftUI
import AppKit
import Observation

@MainActor @Observable
final class StatusAppearance {
    var iconColor: Color { didSet { save(iconColor, key: "statusIconColor") } }
    var textColor: Color { didSet { save(textColor, key: "statusTextColor") } }
    init() {
        iconColor = Self.load("statusIconColor")
        textColor = Self.load("statusTextColor")
    }
    private static func load(_ key: String) -> Color {
        guard let values = UserDefaults.standard.array(forKey: key) as? [Double], values.count == 3 else { return .white }
        return Color(.sRGB, red: values[0], green: values[1], blue: values[2], opacity: 1)
    }
    private func save(_ color: Color, key: String) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)], forKey: key)
    }
}

struct StatusAppearanceView: View {
    @Bindable var appearance: StatusAppearance
    var body: some View {
        Form {
            Section("Floating status") {
                ColorPicker("Icon color", selection: $appearance.iconColor, supportsOpacity: false)
                ColorPicker("Text color", selection: $appearance.textColor, supportsOpacity: false)
                HStack(spacing: 8) {
                    Image(systemName: "pencil.line").foregroundStyle(appearance.iconColor)
                    Text("Recording app activity").foregroundStyle(appearance.textColor)
                }
                .font(.system(size: 11, weight: .medium))
                .padding(12).background(.black, in: RoundedRectangle(cornerRadius: 8))
                Text("Colors update immediately and are saved for next time. Click the floating status to open Conre; pause or resume in App awareness.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset colors") { appearance.iconColor = .white; appearance.textColor = .white }
            }
        }.formStyle(.grouped)
    }
}
