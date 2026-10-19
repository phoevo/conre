import Foundation

/// Copy once when leaving the sandbox; never overwrite current data or remove originals.
@MainActor
struct LegacyStorageMigration {
    static func copyMissingFiles(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        for name in ["working-memory.json", "raw-observations.json"] {
            let old = source.appending(path: name)
            let new = destination.appending(path: name)
            guard !manager.fileExists(atPath: new.path), manager.fileExists(atPath: old.path) else { continue }
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            try manager.copyItem(at: old, to: new)
        }
    }
    static func prepare() -> String? {
        guard !UserDefaults.standard.bool(forKey: "didMigrateSandboxStorage") else { return nil }
        let oldLibrary = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/phoevo.conre/Data/Library")
        do {
            try copyMissingFiles(from: oldLibrary.appending(path: "Application Support/Conre"),
                                 to: URL.applicationSupportDirectory.appending(path: "Conre"))
            let preferences = oldLibrary.appending(path: "Preferences/phoevo.conre.plist")
            if FileManager.default.fileExists(atPath: preferences.path) {
                let data = try Data(contentsOf: preferences)
                let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
                let defaults = UserDefaults.standard
                for key in ["approvedApplicationIDs", "observationPaused", "statusIconColor", "statusTextColor"] where defaults.object(forKey: key) == nil {
                    if let value = values[key] { defaults.set(value, forKey: key) }
                }
            }
            UserDefaults.standard.set(true, forKey: "didMigrateSandboxStorage")
            return nil
        } catch {
            return "Previous sandbox data could not be fully copied: \(error.localizedDescription). Original files are preserved."
        }
    }
}
