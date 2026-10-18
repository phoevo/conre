import SwiftUI

struct ContentView: View {
    let memory: WorkingMemoryStore
    let observer: ActivityObserver

    var body: some View {
        TimelineView(memory: memory, observer: observer)
    }
}
