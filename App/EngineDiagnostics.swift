import Foundation

enum EngineDiagnostics {
    static var log: URL { GameFiles.documents.appendingPathComponent("engine-native.log") }
    static var failure: URL { GameFiles.documents.appendingPathComponent("engine-failure.txt") }
    static func begin(root: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: GameFiles.documents, withIntermediateDirectories: true)
        let previous = GameFiles.documents.appendingPathComponent("engine-native.previous.log")
        if manager.fileExists(atPath: log.path) {
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: log, to: previous)
        }
        try? manager.removeItem(at: failure)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let header = "ZonePort \(version) · \(Date().ISO8601Format())\nSystem: \(ProcessInfo.processInfo.operatingSystemVersionString)\nPhysical memory: \(ProcessInfo.processInfo.physicalMemory) bytes\nGame folder: \(root.lastPathComponent)\nChecking prepared data and installing engine support.\n"
        try Data(header.utf8).write(to: log, options: .atomic)
    }
    static func recordFailure(_ message: String) {
        try? Data(("ZonePort startup failure\n\(Date().ISO8601Format())\n\(message)\n").utf8).write(to: failure, options: .atomic)
    }
    static var files: [URL] {
        [log, failure].filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
