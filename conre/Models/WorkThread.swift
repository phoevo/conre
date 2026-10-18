import Foundation

struct WorkThread: Identifiable, Codable, Equatable {
    enum Status: String, Codable { case active, paused, completed, archived }

    var id: UUID = UUID()
    var title: String
    var parentThreadID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var status: Status = .active
}
