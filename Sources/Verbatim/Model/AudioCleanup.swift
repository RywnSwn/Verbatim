import Foundation

/// Step 9: audio is deleted for good a set number of days after a recording
/// (Settings > Storage, 7 by default). Text is kept forever. Never deletes
/// audio whose text isn't finished, audio that's playing, or a recording
/// marked Keep Audio. Checks at launch and every hour.
@MainActor
enum AudioCleanup {
    static let daysKey = "audioKeepDays"
    /// 0 = keep forever.
    static let choices = [3, 7, 14, 30, 0]
    /// When this feature first ran: nothing is deleted in the 2 days after
    /// that, so an update never wipes audio without a warning first.
    private static let firstRunKey = "audioCleanupSince"

    static var days: Int {
        UserDefaults.standard.object(forKey: daysKey) as? Int ?? 7
    }

    private static var task: Task<Void, Never>?

    static func start() {
        if UserDefaults.standard.object(forKey: firstRunKey) == nil {
            UserDefaults.standard.set(Date(), forKey: firstRunKey)
        }
        guard task == nil else { return }
        task = Task {
            try? await Task.sleep(for: .seconds(30)) // let launch settle
            while !Task.isCancelled {
                sweep()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    /// When this recording's audio goes, or nil if it doesn't.
    static func deleteDate(_ info: RecordingInfo) -> Date? {
        let d = days
        guard d > 0, info.hasAudio, !info.isActive, info.keepAudio != true else { return nil }
        // Imports count from when they were added, not the file's own date.
        let from = info.importedFrom != nil ? RecordingStore.addedDate(info.id) ?? Date() : (info.endedAt ?? info.createdAt)
        var due = from.addingTimeInterval(Double(d) * 86_400)
        if let first = UserDefaults.standard.object(forKey: firstRunKey) as? Date {
            due = max(due, first.addingTimeInterval(2 * 86_400))
        }
        return due
    }

    /// Whole days left, for the sidebar ("audio deletes in 2 days").
    static func daysLeft(_ info: RecordingInfo) -> Int? {
        guard let due = deleteDate(info) else { return nil }
        return max(0, Int(ceil(due.timeIntervalSinceNow / 86_400)))
    }

    static func sweep() {
        let model = RecorderModel.shared
        var count = 0
        for info in model.recordings {
            guard let due = deleteDate(info), due <= Date(),
                  model.audioDeleteBlocker(info.id) == nil,
                  !Transcriber.shared.isUnfinished(info.id),
                  Playback.shared.id != info.id else { continue }
            if model.removeAudioForGood(info.id) { count += 1 }
        }
        guard count > 0 else { return }
        let text = count == 1
            ? "Deleted old audio from 1 recording to save space. The text stays."
            : "Deleted old audio from \(count) recordings to save space. The text stays."
        if model.isBusy { model.flash(text) } else { model.show(text) }
    }
}
