import Foundation

/// Speaker labels (step 7). The speaker model only tells voices apart. Names
/// come from here: the voice that says the most is the teacher (name from
/// Settings, default Mr. Yurt), every other voice shows as Student. Ryan can
/// fix any line, or a whole voice, by clicking its label.
///
/// What a line shows, first match wins:
/// 1. `Line.speaker`: Ryan picked it for this line.
/// 2. `LiveText.voiceNames[voice]`: Ryan picked it for the whole voice.
/// 3. The voice says the most in its listening session: teacher. Else student.
/// No voice (old recordings, no speaker model yet): no label.
enum Speakers {
    static let teacherKey = "teacherName"
    static let studentKey = "studentLabel"
    static let teacherDefault = "Mr. Yurt"
    static let studentDefault = "Student"

    /// Stored instead of the names, so changing Settings changes every line.
    static let teacher = "#teacher"
    static let student = "#student"

    static var teacherName: String { setting(teacherKey) ?? teacherDefault }
    static var studentName: String { setting(studentKey) ?? studentDefault }

    private static func setting(_ key: String) -> String? {
        let s = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    /// "#teacher" -> "Mr. Yurt". Names stay as they are.
    static func display(_ choice: String) -> String {
        switch choice {
        case teacher: teacherName
        case student: studentName
        default: choice
        }
    }

    /// Works out labels for one recording's lines.
    struct Labeler {
        var names: [String: String]
        var teachers: Set<Int>

        init(lines: [Transcript.Line], names: [String: String]?) {
            self.names = names ?? [:]
            // Words per voice, then the top voice of each listening session.
            var words: [Int: Int] = [:]
            for l in lines {
                guard let v = l.voice else { continue }
                words[v, default: 0] += l.text.split(whereSeparator: \.isWhitespace).count
            }
            var best: [Int: (voice: Int, words: Int)] = [:]
            for (v, n) in words {
                let session = v / 4
                if let b = best[session], b.words > n || (b.words == n && b.voice < v) { continue }
                best[session] = (v, n)
            }
            teachers = Set(best.values.map { $0.voice })
        }

        /// What the voice shows if Ryan hasn't picked anything for the line.
        func choice(voice: Int) -> String {
            names["\(voice)"] ?? (teachers.contains(voice) ? Speakers.teacher : Speakers.student)
        }

        /// "#teacher", "#student", a name, or nil (no label).
        func choice(_ line: Transcript.Line) -> String? {
            if let s = line.speaker { return s }
            return line.voice.map { choice(voice: $0) }
        }

        func name(_ line: Transcript.Line) -> String? { choice(line).map(Speakers.display) }
    }

    @MainActor
    static func labeler(_ id: UUID) -> Labeler {
        let t = LiveTranscriber.shared.texts[id]
        return Labeler(lines: t?.lines ?? [], names: t?.voiceNames)
    }

    // MARK: - Going over the whole file

    /// Gives lines voices from the speaker model's pass over the whole file.
    /// A line where the voice changes partway is split at the word where it
    /// changes (needs word times; edited lines keep one voice, the one heard
    /// most). A voice change of a single word isn't trusted.
    static func relabel(_ lines: [Transcript.Line], frames: VoiceFrames, base: Int) -> [Transcript.Line] {
        var out: [Transcript.Line] = []
        for line in lines {
            let words = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !line.isLocked, let starts = line.words, starts.count == words.count, words.count > 1 else {
                var l = line
                l.voice = frames.voice(line.start, line.end).map { $0 + base }
                out.append(l)
                continue
            }
            // Voice of each word.
            let voices: [Int?] = words.indices.map { i in
                let end = i + 1 < starts.count ? starts[i + 1] : line.end
                return frames.voice(starts[i], max(end, starts[i] + 0.05)).map { $0 + base }
            }
            // Runs of the same voice. Words with no voice join the run before.
            var runs: [(voice: Int?, from: Int, to: Int)] = []
            for (i, v) in voices.enumerated() {
                if let last = runs.last, v == nil || last.voice == nil || last.voice == v {
                    runs[runs.count - 1].to = i + 1
                    if runs[runs.count - 1].voice == nil { runs[runs.count - 1].voice = v }
                } else {
                    runs.append((v, i, i + 1))
                }
            }
            // One-word runs go into the run before (or after, if first).
            var k = 0
            while runs.count > 1, k < runs.count {
                if runs[k].to - runs[k].from == 1 {
                    if k > 0 {
                        runs[k - 1].to = runs[k].to
                    } else {
                        runs[1].from = runs[0].from
                    }
                    runs.remove(at: k)
                    // Neighbours may now have the same voice: join them.
                    var j = 1
                    while j < runs.count {
                        if runs[j].voice == runs[j - 1].voice {
                            runs[j - 1].to = runs[j].to
                            runs.remove(at: j)
                        } else { j += 1 }
                    }
                    k = 0
                } else {
                    k += 1
                }
            }
            for (n, run) in runs.enumerated() {
                var l = line
                l.text = words[run.from..<run.to].joined(separator: " ")
                l.words = Array(starts[run.from..<run.to])
                l.start = n == 0 ? line.start : starts[run.from]
                l.end = run.to < starts.count ? starts[run.to] : line.end
                l.voice = run.voice
                if n > 0 { l.speaker = nil }
                out.append(l)
            }
        }
        return out
    }
}

// MARK: - Fixing labels (click a label)

extension RecorderModel {
    /// Ryan picked who said this line. If more lines share its voice and show
    /// something else, the bottom bar offers to change them too.
    func setSpeaker(_ id: UUID, start: Double, to choice: String) {
        let live = LiveTranscriber.shared
        guard let line = live.lines(id).first(where: { $0.start == start }) else { return }
        let before = Speakers.labeler(id)
        guard before.choice(line) != choice else { return }
        var changed = line
        changed.speaker = choice
        live.replaceLine(id, start: start, with: changed)

        let name = Speakers.display(choice)
        guard let voice = line.voice else {
            flash("Changed to \(name).")
            return
        }
        let others = live.lines(id).filter { $0.start != start && $0.voice == voice && $0.speaker == nil }
        guard before.choice(voice: voice) != choice, !others.isEmpty else {
            flash("Changed to \(name).")
            return
        }
        let more = others.count == 1 ? "1 more line sounds" : "\(others.count) more lines sound"
        offer("Changed to \(name). \(more) like the same voice.", .changeVoice) { [weak self] in
            self?.setVoice(id, voice: voice, to: choice, count: others.count + 1)
        }
    }

    /// Every line in this voice (that Ryan didn't pick himself) becomes `choice`.
    func setVoice(_ id: UUID, voice: Int, to choice: String, count: Int) {
        let live = LiveTranscriber.shared
        let old = live.texts[id]?.voiceNames?["\(voice)"]
        live.setVoiceName(id, voice: voice, to: choice)
        let name = Speakers.display(choice)
        offerLineUndo(count == 1 ? "Changed 1 line to \(name)." : "Changed \(count) lines to \(name).") {
            LiveTranscriber.shared.setVoiceName(id, voice: voice, to: old)
        }
    }

    /// Names to offer in the label menu: teacher, student, then names Ryan
    /// typed in this recording.
    func speakerNames(_ id: UUID) -> [String] {
        let t = LiveTranscriber.shared.texts[id]
        var names = (t?.lines ?? []).compactMap(\.speaker) + (t?.voiceNames?.values.map { $0 } ?? [])
        names.removeAll { $0 == Speakers.teacher || $0 == Speakers.student }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.sorted()
    }
}
