import SwiftUI

private enum ConreSection: String, CaseIterable {
    case recent = "Recent work"
    case awareness = "Apps"
    case appearance = "Appearance"
    case advanced = "Advanced"
}

struct ContentView: View {
    let memory: WorkingMemoryStore
    let observer: ActivityObserver
    let appearance: StatusAppearance
    var migrationMessage: String? = nil
    let assistant: WorkAssistant
    private var summary: SummaryController { assistant.summary }
    @State private var selectedSection: ConreSection = .recent

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(ConreSection.allCases, id: \.self) { section in
                    Button { selectedSection = section } label: {
                        Text(section.rawValue)
                            .font(.system(size: 12, weight: selectedSection == section ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(selectedSection == section ? Color.accentColor.opacity(0.15) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                }
            }.padding(10)
            Divider()
            if let migrationMessage { Text(migrationMessage).font(.caption).foregroundStyle(.orange).padding() }
            Group {
                switch selectedSection {
                case .recent: RecentWorkView(observer: observer, assistant: assistant)
                case .awareness: ObservationView(observer: observer)
                case .appearance: StatusAppearanceView(appearance: appearance)
                case .advanced: AdvancedView(observer: observer, memory: memory, assistant: assistant)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 500, minHeight: 590)
            .onChange(of: observer.navigateToApps) { _, value in
                if value { selectedSection = .awareness; observer.contextSettingsPresented = false; observer.navigateToApps = false }
            }
            .sheet(isPresented: Binding(get: { observer.contextSettingsPresented }, set: { observer.contextSettingsPresented = $0 })) {
                ContextInspectorView(observer: observer)
            }
    }
}
