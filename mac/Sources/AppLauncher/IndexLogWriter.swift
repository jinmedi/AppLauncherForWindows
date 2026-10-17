#if canImport(AppKit)
import Foundation
import LauncherCore

/// ~/Library/Application Support/AppLauncherForMac/index.log, rewritten after every refresh: which folder
/// roots were used and what each source contributed. This is what to look at when "my folder is not found".
enum IndexLogWriter {
    static func write(index: AppIndex, folderRoots: [String]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = [
            "\(formatter.string(from: Date()))  \(index.count) entries",
            "",
            "[sources]",
        ]

        for report in index.lastReport {
            let status = report.error.map { "FAILED: \($0)" } ?? "\(report.count) entries"
            lines.append("  \(report.source): \(status) (\(Int(report.elapsed * 1000)) ms)")
        }

        lines.append("")
        lines.append("[folder roots]")
        for root in folderRoots {
            let missing = FileManager.default.fileExists(atPath: root) ? "" : "  (missing)"
            lines.append("  \(root)\(missing)")
        }

        do {
            let data = Data((lines.joined(separator: "\n") + "\n").utf8)
            try AppPaths.writeAtomically(data, to: AppPaths.indexLogFile)
        } catch {
            NSLog("[AppLauncher] could not write index.log: %@", String(describing: error))
        }
    }
}
#endif
