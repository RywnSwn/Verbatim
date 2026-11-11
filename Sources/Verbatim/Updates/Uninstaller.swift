import AppKit

/// Verbatim > Remove Verbatim and Its Data…
/// Everything goes to the Trash (not deleted), so it can still be put back.
@MainActor
enum Uninstaller {
    static let bundleID = "com.rywnswn.verbatim"

    private static var dataItems: [URL] {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return [
            lib.appending(path: "Application Support/Verbatim"),
            lib.appending(path: "Caches/\(bundleID)"),
            lib.appending(path: "HTTPStorages/\(bundleID)"),
            lib.appending(path: "Saved Application State/\(bundleID).savedState"),
            lib.appending(path: "Preferences/\(bundleID).plist"),
            // The word list helper (step 8) has to live in FluidAudio's own folder.
            ParakeetEngine.wordSpotterFolder,
        ]
    }

    static func run() {
        guard !RecorderModel.shared.isBusy else {
            RecorderModel.shared.show("Stop recording first, then remove Verbatim.")
            return
        }
        let size = dataItems.reduce(Int64(0)) { $0 + folderSize($1) }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove Verbatim and its data?"
        alert.informativeText = """
        This moves Verbatim, all recordings and transcripts, the speech model and settings \
        (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) in total) to the Trash. \
        You can still get them back from the Trash until you empty it.
        """
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Move to Trash")
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
        for item in dataItems + [Bundle.main.bundleURL] where FileManager.default.fileExists(atPath: item.path) {
            try? FileManager.default.trashItem(at: item, resultingItemURL: nil)
        }
        Updater.run("/usr/bin/tccutil", ["reset", "Microphone", bundleID])
        NSApp.terminate(nil)
    }

    private static func folderSize(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        while let f = e?.nextObject() as? URL {
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
