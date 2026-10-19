import SwiftUI

private enum ConreSection: String, CaseIterable {
    case recent = "Recent work"
    case memory = "Working memory"
    case awareness = "App awareness"
    case appearance = "Appearance"
}

struct ContentView: View {
    let memory: WorkingMemoryStore
    let observer: ActivityObserver
    let appearance: StatusAppearance
    var migrationMessage: String? = nil
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
                case .recent: RecentWorkView(observer: observer)
                case .memory: TimelineView(memory: memory, observer: observer)
                case .awareness: ObservationView(observer: observer)
                case .appearance: StatusAppearanceView(appearance: appearance)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 500, minHeight: 590)
            .sheet(isPresented: Binding(get: { observer.contextSettingsPresented }, set: { observer.contextSettingsPresented = $0 })) {
                ContextInspectorView(observer: observer)
            }
    }
}
