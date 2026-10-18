import SwiftUI

@main
struct conreApp: App {
    @State private var memory = WorkingMemoryStore()
    @State private var observer = ActivityObserver()

    var body: some Scene {
        WindowGroup("Conre") {
            ContentView(memory: memory, observer: observer)
        }
        .defaultSize(width: 420, height: 590)
    }
}
