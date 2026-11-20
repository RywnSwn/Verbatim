import AppKit
import SwiftUI

/// Transcript lines with the time in a left gutter, in full ink. Words still
/// being worked out (Apple's engine) are lighter. Old recordings can have a
/// Whisper part first, then a thin "Old transcript ends at" line.
/// Follows new text only if you're already at the bottom; otherwise a
/// "Jump to live" button shows.
///
/// Speakers (step 7): "Speaker 1:" (or a name Ryan gave) in bold in front of
/// each line. Click it to rename or pick who said it (or right-click > Speaker).
///
/// Picking and editing (Ryan, 2026-11-20, docs/design/LineTools.html): one
/// click picks a line (blue pen line in the margin, nothing opens) and shows its flag, note and
/// + buttons. Double-click or Enter edits (Enter saves, Esc cancels, clicking
/// away saves). Arrow keys move, Delete deletes. Right-click for the rest.
/// With the Marker or Note tool on (`RecorderModel.lineTool`) a click puts a
/// marker or a note on the line instead. While a line is being
/// typed, the rest of the page is covered (`TypingShield`): a click there
/// only saves. Edited lines turn full ink and get a lock; new words never go
/// into them. Every change has Undo in the bottom bar and on ⌘Z.
struct TranscriptList: View {
    @Environment(RecorderModel.self) private var model
    @Environment(LiveTranscriber.self) private var liveTranscriber
    let info: RecordingInfo
    let checked: [Transcript.Line]
    let live: [Transcript.Line]
    /// Where the checked text ends (seconds into the audio), for the divider.
    var checkedUpTo: Double?
    var volatile: String = ""
    var isLive = false
    /// Shown under the header while there are no lines yet ("Listening...").
    /// At the page edge, where the start page's hint is, so pressing Record
    /// doesn't move it.
    var emptyHint: String?
    /// A text link next to the hint, like "Transcribe" (no lines yet).
    var emptyAction: (label: String, run: () -> Void)?

    @AppStorage(TimeStyle.key) private var timeStyle: TimeStyle = .clock
    @AppStorage(TextSize.key) private var textSize = TextSize.normal
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true
    @State private var editing: EditKey?
    /// The line picked with one click. Nothing is typed into it.
    @State private var picked: EditKey?
    @FocusState private var listFocused: Bool
    /// What's typed into the line being edited. Not watched on purpose: the
    /// typing lives in `LineEditor`, so a key press redraws that one line and
    /// not the whole transcript.
    @State private var draft = LineDraft()
    /// The line whose note is being typed (see `Notes`).
    @State private var notingLine: Transcript.Line?
    @State private var noteDraft = LineDraft()
    /// Right-click > Add line below: the empty line being typed under the
    /// line that starts at `below`. It only becomes a real line once it has
    /// text (`saveNewLine`), so an empty one is never saved.
    @State private var adding: NewLine?
    @State private var newDraft = LineDraft()
    /// The recording the open box (line, note or new line) belongs to. This
    /// view is kept when another recording is opened, so saving always goes
    /// here, never into the recording now on screen (UX round 2, A2).
    @State private var boxOwner: UUID?
    /// Its own focus: losing it doesn't save (picking a speaker from the
    /// name menu may take focus). A click away, Enter or leaving saves.
    @FocusState private var newFocused: Bool
    @FocusState private var noteFocused: Bool
    @FocusState private var fieldFocused: Bool
    /// Last time you scrolled by hand, so playing audio doesn't yank the view away.
    @State private var lastUserScroll = Date.distantPast
    /// The line a Marker or Note tool click just went to: the second click of
    /// a double-click there does nothing more (B6).
    @State private var toolClickLine: Double?
    /// Typing a name: for a whole voice (Rename) or one line (Someone else).
    @State private var naming: Naming?
    @State private var nameDraft = ""
    /// Right-click > Add a word to word list (step 8).
    @State private var addingWord = false
    @State private var wordDraft = ""

    private struct Naming {
        var start: Double
        /// Rename this voice everywhere. nil = just this line.
        var voice: Int?
        var oldName: String
        /// For the line being added (not saved yet).
        var newLine = false
    }

    private struct NewLine {
        var below: Double
        /// Who said it: starts as the line above's speaker.
        var speaker: String?
    }

    private var playback: Playback { .shared }
    /// Times in the gutter play from that line (finished recordings with audio).
    private var canPlay: Bool { !isLive && info.hasAudio }

    /// The line being heard right now, while the player is open. Kept up to
    /// date by `PlayheadTracker`, so this view is redrawn when the line
    /// changes, not on every tick of the audio clock.
    @State private var playingRowID: String?

    private struct EditKey: Hashable {
        var source: LineSource
        var start: Double
    }

    private enum Row: Identifiable {
        case line(Transcript.Line, LineSource)
        case checkedUpTo(Double)
        case volatile(String)
        /// "Paused 10:12 to 10:20" between the lines (B2).
        case pause(RecordingInfo.Break)

        var id: String {
            switch self {
            case .line(let l, let s): TranscriptRow.id(s, l.start)
            case .checkedUpTo: "checked"
            case .volatile: "volatile"
            case .pause(let b): "break-\(b.second)-\(b.text.prefix(6))"
            }
        }
    }

    private var rows: [Row] {
        var rows = checked.map { Row.line($0, .checked) }
        if !checked.isEmpty, !live.isEmpty || !volatile.isEmpty, let last = checked.last {
            rows.append(.checkedUpTo(checkedUpTo ?? last.end))
        }
        // Pauses and sleeps go before the first line after them. One still
        // going (paused now) goes at the end.
        var breaks = info.breaks[...]
        for line in live {
            while let b = breaks.first, b.second <= line.start {
                rows.append(.pause(b))
                breaks = breaks.dropFirst()
            }
            rows.append(.line(line, .live))
        }
        if !live.isEmpty { rows += breaks.map { Row.pause($0) } }
        let v = volatile.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty { rows.append(.volatile(v)) }
        return rows
    }

    /// The scrolling list itself. Split from `body` (which adds saving, notes,
    /// search and the alerts) because the Swift compiler gives up on one very
    /// long chain. Keep it in two parts.
    @ViewBuilder private var scroller: some View {
        let labels = Speakers.labeler(info.id)
        let options = labels.options(live)
        let marked = Markers.markedStarts(checked + live, info.markers)
        let notes = Notes.byLine(checked + live, info.notes)
        let rows = self.rows
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.lineGap) {
                RecordingHeader(info: info, lines: checked + live, isLive: isLive)
                    .modifier(TypingShield(active: isTyping) { stopTyping() })
                    .padding(.bottom, 10)
                if rows.isEmpty, let emptyHint {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(emptyHint)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let emptyAction {
                            Button(emptyAction.label, action: emptyAction.run)
                                .buttonStyle(.link)
                                .fontWeight(.medium)
                        }
                    }
                }
                ForEach(rows) { row in
                    // One view per row, always. With a different number of views
                    // per row, the lazy stack has to build every row of the whole
                    // transcript on each change to know what is where.
                    VStack(alignment: .leading, spacing: Theme.lineGap) {
                        switch row {
                        case .line(let line, let source):
                            VStack(alignment: .leading, spacing: Theme.lineGap) {
                                lineRow(line, source, speaker: source == .live ? labels.choice(line) : nil,
                                        name: source == .live ? labels.name(line) : nil, options: options,
                                        marked: marked.contains(line.start), note: notes[line.start])
                                    // The line above a new line: covered too, a click only saves.
                                    .modifier(TypingShield(active: isAddingBelow(line, source)) { stopTyping() })
                                if notingLine?.start == line.start {
                                    noteEditor
                                } else if let note = notes[line.start] {
                                    NoteRow(text: note, shown: query.isEmpty ? nil : highlighted(note, source, line.start, .note)) {
                                        beginNote(line, note)
                                    }
                                }
                                if let offer = model.fixOffer, offer.recordingID == info.id, offer.start == line.start {
                                    fixOfferRow(offer.fix)
                                }
                                if isAddingBelow(line, source), let adding {
                                    newLineEditor(adding, labels: labels, options: options)
                                }
                            }
                            // While a line or note is being typed, every other
                            // line is covered: a click there only saves.
                            .modifier(TypingShield(active: isTyping && !isTyping(on: line, source)) { stopTyping() })
                        case .checkedUpTo(let seconds):
                            HStack(spacing: 10) {
                                Text("Old transcript ends at \(info.timeLabel(seconds, style: timeStyle))")
                                    .font(.system(size: 13, design: .serif).italic())
                                    .foregroundStyle(.secondary)
                                Rectangle().fill(Theme.line).frame(height: 1)
                            }
                            .padding(.leading, 70)
                            .padding(.vertical, 4)
                            .modifier(TypingShield(active: isTyping) { stopTyping() })
                        case .pause(let b):
                            HStack(spacing: 10) {
                                Text(b.text)
                                    .font(.system(size: 13, design: .serif).italic())
                                    .foregroundStyle(.secondary)
                                Rectangle().fill(Theme.line).frame(height: 1)
                            }
                            .padding(.leading, 70)
                            .padding(.vertical, 4)
                            .modifier(TypingShield(active: isTyping) { stopTyping() })
                        case .volatile(let text):
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Color.clear.frame(width: 60, height: 1)
                                Text(text)
                                    .font(Theme.transcript(textSize))
                                    .lineSpacing(Theme.transcriptLineSpacing)
                                    .foregroundStyle(Theme.ink.opacity(0.45))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .modifier(TypingShield(active: isTyping) { stopTyping() })
                        }
                    }
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            // The gaps between lines and the margins count as "away" too.
            .background {
                if isTyping {
                    Color.clear.contentShape(Rectangle()).onTapGesture { stopTyping() }
                }
            }
        }
        .scrollPosition($position)
        .background(Theme.paper)
        .background {
            if !isLive, playback.isShowing(info.id) {
                PlayheadTracker(checked: checked, live: live, playingRowID: $playingRowID)
            }
        }
        .onChange(of: !isLive && playback.isShowing(info.id)) { _, showing in
            if !showing { playingRowID = nil }
        }
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 60
        } action: { _, bottom in
            atBottom = bottom
        }
        .onChange(of: live.count + checked.count) {
            if followsLive { withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(edge: .bottom) } }
        }
        .onChange(of: volatile) {
            if followsLive { position.scrollTo(edge: .bottom) }
        }
    }

    var body: some View {
        scroller
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { movePick(-1) }
        .onKeyPress(.downArrow) { movePick(1) }
        .onKeyPress(.return) {
            guard !isTyping, let p = pickedLine() else { return .ignored }
            begin(p.line, p.source)
            return .handled
        }
        .onKeyPress(.escape) {
            guard !isTyping, picked != nil else { return .ignored }
            picked = nil
            return .handled
        }
        .onDeleteCommand { deletePicked() }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let tool = model.lineTool {
                LineToolBand(tool: tool) { model.lineTool = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.18), value: model.lineTool)
        .onChange(of: model.lineTool) { _, tool in
            // Picking up a tool saves and closes whatever was being typed.
            if tool != nil {
                stopTyping()
                picked = nil
            }
        }
        .onChange(of: fieldFocused) {
            // Clicking somewhere else saves, like a text field in Notes.
            if !fieldFocused, editing != nil { save() }
        }
        .onDisappear { stopTyping() }
        .onChange(of: info.id) {
            // Another recording opened: save and close what was open in the
            // old one, and forget its picked line and popups.
            stopTyping()
            picked = nil
            naming = nil
            addingWord = false
        }
        .onChange(of: live.count) { keepNewLineAnchored() }
        .onChange(of: noteFocused) {
            if !noteFocused, notingLine != nil { saveNote() }
        }
        .onChange(of: model.noteRequest, initial: true) { _, request in
            takeNoteRequest(request)
        }
        .onScrollPhaseChange { _, phase in
            let byHand: [ScrollPhase] = [.interacting, .tracking, .decelerating]
            if byHand.contains(phase) { lastUserScroll = Date() }
        }
        .onChange(of: playingRowID) { _, id in
            // Follow the audio, unless you scrolled or moved the picked line in
            // the last 8 seconds, or are typing (line, note or new line, B5) or searching.
            guard let id, playback.isPlaying, !isTyping, model.searchText.isEmpty,
                  Date().timeIntervalSince(lastUserScroll) > 8 else { return }
            withAnimation(.easeOut(duration: 0.3)) { position.scrollTo(id: id, anchor: .center) }
        }
        .onChange(of: model.matchJump) { jumpToMatch() }
        .alert(naming?.voice != nil ? "Rename \(naming?.oldName ?? "")" : "Who said this line?",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $nameDraft)
            Button("OK") {
                let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if let n = naming, !name.isEmpty {
                    if n.newLine {
                        adding?.speaker = name
                        Task { @MainActor in newFocused = true }
                    } else if let voice = n.voice {
                        model.renameVoice(info.id, voice: voice, to: name)
                    } else {
                        model.setSpeaker(info.id, start: n.start, to: name)
                    }
                }
                naming = nil
            }
            Button("Cancel", role: .cancel) { naming = nil }
        } message: {
            Text(naming?.voice != nil
                 ? "Every line in this voice changes. Names you type are offered in your other recordings too."
                 : "Only this line changes. Names you type are offered in your other recordings too.")
        }
        .alert("Add to the word list", isPresented: $addingWord) {
            TextField("Name, like Kweku Tsin", text: $wordDraft)
            Button("Add") {
                model.addToWordList(wordDraft)
                wordDraft = ""
            }
            Button("Cancel", role: .cancel) { wordDraft = "" }
        } message: {
            Text("Verbatim listens for it, live and in files, and writes it the way you spell it here. See them all in Settings > Words.")
        }
        .onAppear { if !model.searchText.isEmpty { jumpToMatch() } }
        .overlay(alignment: .bottom) {
            if isLive, !atBottom {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .bottom) }
                } label: {
                    Label("Jump to live", systemImage: "arrow.down")
                }
                .buttonStyle(.ink)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
    }

    /// Don't scroll away from a line you're editing or a search hit.
    private var followsLive: Bool {
        isLive && atBottom && !isTyping && model.searchText.isEmpty
    }

    // MARK: - Search

    private var query: String { model.searchText.trimmingCharacters(in: .whitespaces) }

    private var matches: [SearchMatch] { model.searchMatches(info.id) }

    private var currentMatch: SearchMatch? {
        let all = matches
        guard !all.isEmpty else { return nil }
        return all[min(model.matchIndex, all.count - 1)]
    }

    private func jumpToMatch() {
        guard let match = currentMatch else { return }
        withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(id: match.rowID, anchor: .center) }
    }

    /// The line's text with search hits in yellow; the current hit stronger.
    private func highlighted(_ text: String, _ source: LineSource, _ start: Double,
                             _ part: SearchMatch.Part = .text) -> AttributedString {
        let ranges = RecorderModel.ranges(of: query, in: text)
        guard !ranges.isEmpty else { return AttributedString(text) }
        let current = currentMatch.flatMap { $0.source == source && $0.start == start && $0.part == part ? $0.occurrence : nil }
        var result = AttributedString()
        var cursor = text.startIndex
        for (k, r) in ranges.enumerated() {
            result += AttributedString(String(text[cursor..<r.lowerBound]))
            var hit = AttributedString(String(text[r]))
            hit.backgroundColor = k == current ? Theme.highlightCurrent : Theme.highlight
            hit.foregroundColor = Theme.ink
            result += hit
            cursor = r.upperBound
        }
        result += AttributedString(String(text[cursor...]))
        return result
    }

    /// "Mr. Yurt:" in bold, then the line.
    static func labelled(_ text: Text, _ name: String?) -> Text {
        guard let name else { return text }
        return Text("\(Text(name + ":").fontWeight(.semibold)) \(text)")
    }

    /// Rename this voice everywhere, or pick who said this line: this
    /// recording's speakers, names used before, or a new name.
    @ViewBuilder private func speakerItems(_ line: Transcript.Line, current: String?, name: String?,
                                           options: [Speakers.SpeakerOption]) -> some View {
        if let voice = line.voice, let name {
            Button("Rename \(name) everywhere…") {
                nameDraft = name.hasPrefix("Speaker ") ? "" : name
                naming = Naming(start: line.start, voice: voice, oldName: name)
            }
            Divider()
        }
        let pick = Binding<String>(
            get: { current ?? "" },
            set: { model.setSpeaker(info.id, start: line.start, to: $0) }
        )
        Picker("This line is:", selection: pick) {
            ForEach(options, id: \.choice) { Text($0.name).tag($0.choice) }
        }
        .pickerStyle(.inline)
        Button("Someone else…") {
            nameDraft = ""
            naming = Naming(start: line.start, voice: nil, oldName: name ?? "")
        }
        let past = Speakers.recentNames
        if !past.isEmpty {
            Divider()
            // A Mac menu can't hold an X button, so forgetting is a submenu.
            // The same list, with X buttons, is in Settings > Voices.
            Menu("Forget a Name") {
                ForEach(past, id: \.self) { n in
                    Button(n) {
                        guard let i = Speakers.forget(n) else { return }
                        model.offerLineUndo("\(n) won't be offered as a speaker any more.") {
                            Speakers.restore(n, at: i)
                        }
                    }
                }
            }
        }
    }

    private func lineRow(_ line: Transcript.Line, _ source: LineSource, speaker: String?, name: String?,
                         options: [Speakers.SpeakerOption], marked: Bool, note: String?) -> some View {
        let key = EditKey(source: source, start: line.start)
        let isEditing = editing == key
        let isPicked = picked == key && !isEditing
        let tool = isEditing ? nil : model.lineTool
        let isPlaying = playingRowID == TranscriptRow.id(source, line.start)
        // Gutter 60 + gap 10 = the 70 pt that notes and offers line up with.
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            timeGutter(line, isPlaying: isPlaying || isPicked)
                .overlay(alignment: .leading) {
                    // The flag sits just left of the time, so long times still fit.
                    if marked {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.ink)
                            .offset(x: -15)
                            .help("Marked. Right-click the line to remove it.")
                            .accessibilityLabel("Marked")
                    }
                }
            if isEditing {
                LineEditor(draft: draft, focused: $fieldFocused, font: Theme.transcript(textSize),
                           onSave: { save() }, onCancel: { cancel() })
            } else {
                Group {
                    if !query.isEmpty {
                        if let name {
                            Text("\(Text(highlighted(name + ":", source, line.start, .speaker)).fontWeight(.semibold)) \(Text(highlighted(line.text, source, line.start)))")
                        } else {
                            Text(highlighted(line.text, source, line.start))
                        }
                    } else if isPlaying {
                        PlayingLineText(line: line, name: name)
                    } else {
                        Self.labelled(Text(line.text), name)
                    }
                }
                    .overlay(alignment: .topLeading) {
                        if let name {
                            SpeakerLabelButton(name: name) { speakerItems(line, current: speaker, name: name, options: options) }
                        }
                    }
                    .font(Theme.transcript(textSize))
                    .lineSpacing(Theme.transcriptLineSpacing)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if line.isLocked, !isEditing {
                Button {
                    model.unlockLine(info.id, source, start: line.start)
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("You edited this line. Click to unlock.")
                .accessibilityLabel("Unlock line")
            }
            if isPicked, tool == nil {
                lineActions(line, source, speaker: speaker, marked: marked, note: note)
            }
        }
        .background {
            if isPlaying {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.line.opacity(0.7))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -5)
            }
        }
        .modifier(LineHighlight(picked: isPicked, tool: tool))
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { tapped(line, source, marked: marked, note: note) } }
        .contextMenu {
            if canPlay {
                Button("Play from here") { model.playAudio(info.id, from: line.start) }
                Divider()
            }
            Button("Copy this line") { model.copyLines(info, [line]) }
            Button("Copy from here down") { model.copyLines(info, linesFrom(line, source)) }
            Divider()
            Button("Edit line") { begin(line, source) }
            if source == .live {
                Button("Add line below") { beginNewLine(below: line, speaker: speaker) }
            }
            if marked {
                Button("Remove marker") { model.removeMarker(info.id, line: line) }
            } else {
                Button("Add marker here") { model.addMarker(info.id, line: line) }
            }
            Button(note == nil ? "Add note" : "Edit note") { beginNote(line, note ?? "") }
            if note != nil {
                Button("Delete note") { model.setNote(info.id, line: line, text: "") }
            }
            if source == .live {
                Menu("Speaker") { speakerItems(line, current: speaker, name: name, options: options) }
            }
            Button("Add a word to word list…") { addingWord = true }
            Button("Delete line") { model.deleteLine(info.id, source, start: line.start) }
            if line.isLocked {
                Divider()
                Button("Unlock") { model.unlockLine(info.id, source, start: line.start) }
            }
        }
        // Press (VoiceOver, the smoke test's clicks): same as one click.
        .accessibilityAction { if !isEditing { tapped(line, source, marked: marked, note: note) } }
        .accessibilityAction(named: "Edit line") { begin(line, source) }
        .accessibilityAction(named: "Delete line") { model.deleteLine(info.id, source, start: line.start) }
        .accessibilityAction(named: "Add line below") {
            if source == .live { beginNewLine(below: line, speaker: speaker) }
        }
    }

    /// Under a line Ryan just fixed: remember it for next time? (step 8)
    private func fixOfferRow(_ fix: PhraseFix) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Fix “\(fix.from)” to “\(fix.to)” in future transcripts too?")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Remember") { model.rememberFix() }
                .buttonStyle(.link)
                .fontWeight(.medium)
                .help("New text gets this fix by itself. The rest of this transcript is fixed too, with Undo.")
            Button("Just this once") { model.dismissFix() }
                .buttonStyle(.link)
        }
        .font(.callout)
        .padding(.leading, 70)
        .padding(.top, -4)
        .transition(.opacity)
    }

    /// The time on the left. On finished recordings it's a button: click to
    /// hear the audio from that line (the text itself still edits).
    @ViewBuilder private func timeGutter(_ line: Transcript.Line, isPlaying: Bool) -> some View {
        let label = Text(info.timeLabel(line.start, style: timeStyle))
            .font(isPlaying ? .callout.weight(.semibold) : .callout)
            .monospacedDigit()
            .foregroundStyle(isPlaying ? Theme.accent : .secondary)
            // One line always: "10:42 AM" wrapped its "M" onto a second
            // line in the old 52 pt gutter (Ryan, 2026-11-19).
            .lineLimit(1)
            .fixedSize()
            .frame(width: 60, alignment: .trailing)
        if canPlay {
            Button {
                model.playAudio(info.id, from: line.start)
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Play from here")
            .accessibilityLabel("Play from \(info.timeLabel(line.start, style: timeStyle))")
        } else {
            label
        }
    }

    private func linesFrom(_ line: Transcript.Line, _ source: LineSource) -> [Transcript.Line] {
        let all = checked + live
        let index = source == .checked
            ? checked.firstIndex { $0.start == line.start }
            : live.firstIndex { $0.start == line.start }.map { $0 + checked.count }
        guard let index else { return [line] }
        return Array(all[index...])
    }

    /// The note being typed, under its line: a pencil, then the field.
    private var noteEditor: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "pencil")
                .font(.caption)
                .foregroundStyle(Theme.note)
            VStack(alignment: .leading, spacing: 5) {
                LineEditor(draft: noteDraft, focused: $noteFocused, font: .callout,
                           prompt: "What the mic can't hear, like what's on the board",
                           onSave: { saveNote() }, onCancel: { finishNote() })
                Text("Enter saves. Esc cancels. Empty deletes the note.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 70)
        .padding(.top, -8)
    }

    /// ⇧⌘N or the Note button: type a note on the line being said now.
    private func takeNoteRequest(_ request: RecorderModel.NoteRequest?) {
        guard let request, request.id == info.id else { return }
        model.noteRequest = nil
        let all = checked + live
        guard let line = all.first(where: { $0.start == request.start }) else { return }
        let isLiveLine = live.contains { $0.start == request.start }
        let note = Notes.byLine(all, info.notes)[line.start]
        beginNote(line, note ?? "")
        position.scrollTo(id: TranscriptRow.id(isLiveLine ? .live : .checked, line.start), anchor: .center)
    }

    private func beginNote(_ line: Transcript.Line, _ text: String) {
        stopTyping()
        noteDraft = LineDraft() // a new box, same reason as in `begin`
        noteDraft.text = text
        boxOwner = info.id
        notingLine = line
        Task { @MainActor in noteFocused = true }
    }

    private func saveNote() {
        guard let line = notingLine else { return }
        finishNote()
        model.setNote(boxOwner ?? info.id, line: line, text: noteDraft.text)
    }

    private func finishNote() {
        notingLine = nil
        noteFocused = false
    }

    /// A line, a note or a new line is being typed. Only one at a time.
    private var isTyping: Bool { editing != nil || notingLine != nil || adding != nil }

    private func isAddingBelow(_ line: Transcript.Line, _ source: LineSource) -> Bool {
        source == .live && adding?.below == line.start
    }

    /// This line (or its note) is the one being typed: it stays uncovered.
    private func isTyping(on line: Transcript.Line, _ source: LineSource) -> Bool {
        editing == EditKey(source: source, start: line.start) || notingLine?.start == line.start
            || isAddingBelow(line, source) // the new line under it (the line itself has its own cover)
    }

    /// A click anywhere else while typing: save and stop, nothing more.
    private func stopTyping() {
        if editing != nil { save() }
        if notingLine != nil { saveNote() }
        if adding != nil { saveNewLine() }
    }

    private func begin(_ line: Transcript.Line, _ source: LineSource) {
        stopTyping()
        // A new box for every edit. The old field writes its text one last
        // time as it closes; into a shared box that landed in the line you
        // clicked next and replaced it (Ryan, 2026-11-19).
        draft = LineDraft()
        draft.text = line.text
        boxOwner = info.id
        editing = EditKey(source: source, start: line.start)
        picked = editing // after saving, the line stays picked
        if source == .live { liveTranscriber.editing = (info.id, line.start) }
        Task { @MainActor in fieldFocused = true }
    }

    // MARK: - Picking a line, line tools

    /// One click: with a tool, put a marker (or take it off) or open a note.
    /// Without: pick the line. A double-click edits it.
    private func tapped(_ line: Transcript.Line, _ source: LineSource, marked: Bool, note: String?) {
        // B6: a double-click with a tool used to add then remove the flag, or
        // open the line's text instead of the note.
        let clicks = NSApp.currentEvent?.clickCount ?? 1
        if clicks >= 2, toolClickLine == line.start { return }
        toolClickLine = nil
        switch model.lineTool {
        case .marker?:
            toolClickLine = line.start
            if marked { model.removeMarker(info.id, line: line) } else { model.addMarker(info.id, line: line) }
        case .note?:
            toolClickLine = line.start
            model.lineTool = nil // goes down after one note: you type it right away
            beginNote(line, note ?? "")
        case nil:
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                begin(line, source)
            } else {
                stopTyping()
                picked = EditKey(source: source, start: line.start)
                listFocused = true
            }
        }
    }

    /// Flag, note and + on the picked line, so they're never hidden in the
    /// right-click menu only.
    @ViewBuilder private func lineActions(_ line: Transcript.Line, _ source: LineSource, speaker: String?,
                                          marked: Bool, note: String?) -> some View {
        HStack(spacing: 2) {
            LineActionButton(icon: marked ? "flag.slash" : "flag", help: marked ? "Remove marker" : "Add marker here") {
                if marked { model.removeMarker(info.id, line: line) } else { model.addMarker(info.id, line: line) }
            }
            LineActionButton(icon: "pencil", help: note == nil ? "Add note" : "Edit note") {
                beginNote(line, note ?? "")
            }
            if source == .live {
                LineActionButton(icon: "plus", help: "Add a line below") {
                    beginNewLine(below: line, speaker: speaker)
                }
            }
        }
        .transition(.opacity)
    }

    /// The lines in the order they're shown, for the arrow keys.
    private var lineKeys: [EditKey] {
        checked.map { EditKey(source: .checked, start: $0.start) } + live.map { EditKey(source: .live, start: $0.start) }
    }

    private func pickedLine() -> (line: Transcript.Line, source: LineSource)? {
        guard let p = picked else { return nil }
        let lines = p.source == .checked ? checked : live
        return lines.first { $0.start == p.start }.map { ($0, p.source) }
    }

    private func movePick(_ step: Int) -> KeyPress.Result {
        guard !isTyping, let p = picked else { return .ignored }
        let keys = lineKeys
        guard let i = keys.firstIndex(of: p) else { return .ignored }
        let next = keys[max(0, min(keys.count - 1, i + step))]
        picked = next
        lastUserScroll = Date() // the audio doesn't pull the view back (B5)
        position.scrollTo(id: TranscriptRow.id(next.source, next.start))
        return .handled
    }

    private func deletePicked() {
        guard !isTyping, let p = pickedLine() else { return }
        let keys = lineKeys
        let i = keys.firstIndex(of: EditKey(source: p.source, start: p.line.start)) ?? 0
        model.deleteLine(info.id, p.source, start: p.line.start)
        let rest = keys.filter { $0 != picked }
        picked = rest.isEmpty ? nil : rest[min(i, rest.count - 1)]
    }

    // MARK: - Add line below

    private func beginNewLine(below line: Transcript.Line, speaker: String?) {
        stopTyping()
        newDraft = LineDraft() // a new box, same reason as in `begin`
        boxOwner = info.id
        adding = NewLine(below: line.start, speaker: speaker)
        Task { @MainActor in newFocused = true }
    }

    private func saveNewLine() {
        guard let a = adding else { return }
        finishNewLine()
        model.addLine(boxOwner ?? info.id, below: a.below, text: newDraft.text, speaker: a.speaker)
    }

    /// A pass over the file can rebuild the lines while a new line is open:
    /// if the line it sits under is gone, it moves under the line now there.
    private func keepNewLineAnchored() {
        // Only in its own recording: switching recordings changes `live` too.
        guard let a = adding, boxOwner == info.id, !live.contains(where: { $0.start == a.below }) else { return }
        if let line = live.last(where: { $0.start <= a.below }) ?? live.first {
            adding?.below = line.start
        } else {
            finishNewLine()
        }
    }

    private func finishNewLine() {
        adding = nil
        newFocused = false
    }

    /// The new line under its line: the time it will get, the speaker (click
    /// to change), then the field. Lines up with the lines around it.
    @ViewBuilder private func newLineEditor(_ a: NewLine, labels: Speakers.Labeler,
                                            options: [Speakers.SpeakerOption]) -> some View {
        let time = RecorderModel.newLineTimes(live, below: a.below)?.start ?? a.below
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(info.timeLabel(time, style: timeStyle))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 60, alignment: .trailing)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let s = a.speaker {
                        SpeakerLabelButton(name: labels.display(s), solid: true) { newLineSpeakerItems(options) }
                    }
                    LineEditor(draft: newDraft, focused: $newFocused, font: Theme.transcript(textSize),
                               prompt: "New line", onSave: { saveNewLine() }, onCancel: { finishNewLine() })
                }
                Text("Enter adds the line. Esc cancels.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .transition(.opacity)
    }

    /// The name menu of the new line: same people as the other lines.
    @ViewBuilder private func newLineSpeakerItems(_ options: [Speakers.SpeakerOption]) -> some View {
        let pick = Binding<String>(
            get: { adding?.speaker ?? "" },
            set: {
                adding?.speaker = $0
                Task { @MainActor in newFocused = true } // back to typing
            }
        )
        Picker("This line is:", selection: pick) {
            ForEach(options, id: \.choice) { Text($0.name).tag($0.choice) }
        }
        .pickerStyle(.inline)
        Button("Someone else…") {
            nameDraft = ""
            naming = Naming(start: adding?.below ?? 0, voice: nil, oldName: "", newLine: true)
        }
    }

    private func save() {
        guard let key = editing else { return }
        finish()
        model.editLine(boxOwner ?? info.id, key.source, start: key.start, text: draft.text)
    }

    private func cancel() {
        finish()
    }

    private func finish() {
        editing = nil
        fieldFocused = false
        liveTranscriber.editing = nil
    }
}

extension RecordingInfo {
    /// Times in the style picked in Settings.
    func timeLabel(_ seconds: Double) -> String { timeLabel(seconds, style: TimeStyle.current) }

    /// Clock time (10:42) or time since start (37:12). Imported files always
    /// use time since start: there is no clock time for them.
    func timeLabel(_ seconds: Double, style: TimeStyle) -> String {
        if importedFrom != nil || style == .sinceStart {
            let s = Int(seconds)
            return s >= 3600
                ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                : String(format: "%d:%02d", s / 60, s % 60)
        }
        return wallTime(atSecond: seconds).formatted(.dateTime.hour().minute())
    }
}

/// While a line is being typed, lies over the rest of the page so a click
/// there only saves that line. Before, the click also opened the line under
/// it, and the old text could land in it (Ryan, 2026-11-19).
struct TypingShield: ViewModifier {
    let active: Bool
    let onTap: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
                    .pointerStyle(.default)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The text of the line being edited, shared between the list (which saves
/// it) and `LineEditor` (which types into it). A plain box, not watched.
final class LineDraft {
    var text = ""
}

/// The text field of the line being edited. It keeps its own copy of the
/// text, so typing redraws this field only. Before, every key press redrew
/// the whole transcript, and typing got slow in a long recording.
struct LineEditor: View {
    let draft: LineDraft
    var focused: FocusState<Bool>.Binding
    let font: Font
    let prompt: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var text: String

    init(draft: LineDraft, focused: FocusState<Bool>.Binding, font: Font, prompt: String = "Line",
         onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.draft = draft
        self.focused = focused
        self.font = font
        self.prompt = prompt
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: draft.text)
    }

    var body: some View {
        let typed = Binding<String>(
            get: { text },
            set: {
                text = $0
                draft.text = $0
            }
        )
        TextField(prompt, text: typed, axis: .vertical)
            .textFieldStyle(.plain)
            .font(font)
            .lineSpacing(Theme.transcriptLineSpacing)
            .focused(focused)
            .onSubmit { onSave() }
            .onExitCommand { onCancel() }
            .padding(.vertical, 2)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.accent).frame(height: 1).offset(y: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A note under its line: a pencil and the text, in a warm color and
/// smaller than the transcript, so it never looks like speech. Click to change it.
private struct NoteRow: View {
    let text: String
    /// The note with search hits marked, while searching.
    var shown: AttributedString?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "pencil")
                    .font(.caption)
                Text(shown ?? AttributedString(text))
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.note)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.ink.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.leading, 64)
        .padding(.top, -8)
        .help("Click to change this note")
        .accessibilityLabel("Note: \(text)")
        .accessibilityHint("Edit note")
    }
}

/// Watches the audio clock and reports which line is being heard. Draws
/// nothing. It is the only thing redrawn on every tick, so the transcript
/// itself stays still until the line changes.
private struct PlayheadTracker: View {
    let checked: [Transcript.Line]
    let live: [Transcript.Line]
    @Binding var playingRowID: String?

    private var current: String? {
        let t = Playback.shared.time + 0.05
        if let l = live.last(where: { $0.start <= t }) { return TranscriptRow.id(.live, l.start) }
        if let l = checked.last(where: { $0.start <= t }) { return TranscriptRow.id(.checked, l.start) }
        return nil
    }

    var body: some View {
        Color.clear
            .onChange(of: current, initial: true) { _, id in playingRowID = id }
    }
}

/// The playing line with the word being heard marked. Its own view, so the
/// audio clock redraws this one line and nothing else. Uses the word times
/// Parakeet gave (step 5c). Older or edited lines have none, so the word is
/// estimated: the line's time shared out by word length, with a little
/// extra after commas and full stops.
private struct PlayingLineText: View {
    let line: Transcript.Line
    let name: String?

    var body: some View {
        TranscriptList.labelled(highlighted(at: Playback.shared.time), name)
            .textRenderer(WordMarkRenderer(color: Theme.accent.opacity(0.22)))
    }

    private func highlighted(at time: Double) -> Text {
        let text = line.text
        var words: [Range<String.Index>] = []
        var i = text.startIndex
        while i < text.endIndex {
            while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
            let start = i
            while i < text.endIndex, !text[i].isWhitespace { i = text.index(after: i) }
            if start < i { words.append(start..<i) }
        }
        guard !words.isEmpty else { return Text(text) }
        var current = words.count - 1
        if let starts = line.words, starts.count == words.count {
            let t = time + 0.05
            current = max(0, (starts.lastIndex { $0 <= t }) ?? 0)
            return marked(text, words[current])
        }
        guard line.end > line.start else { return Text(text) }
        let weights: [Double] = words.map { r in
            let w = text[r]
            var weight = Double(w.count) + 2
            if let last = w.last {
                if ".?!".contains(last) { weight += 5 } else if ",;:".contains(last) { weight += 3 }
            }
            return weight
        }
        let total = weights.reduce(0, +)
        let fraction = (time - line.start) / (line.end - line.start)
        let target = min(max(fraction, 0), 1) * total
        var sum = 0.0
        for (k, w) in weights.enumerated() {
            sum += w
            if target < sum { current = k; break }
        }
        return marked(text, words[current])
    }

    /// The word gets a `WordMark`, which `WordMarkRenderer` draws as a soft
    /// rounded box behind it (a plain text background has square corners).
    private func marked(_ text: String, _ word: Range<String.Index>) -> Text {
        let before = Text(String(text[..<word.lowerBound]))
        let mark = Text(String(text[word])).customAttribute(WordMark())
        let after = Text(String(text[word.upperBound...]))
        return Text("\(before)\(mark)\(after)")
    }
}

/// Sits exactly on top of the bold "Mr. Yurt:" (same text, see-through), so
/// clicking the name opens the menu right there. Shaded on hover.
struct SpeakerLabelButton<Items: View>: View {
    let name: String
    /// Drawn by itself (on a line being added), not over a name under it.
    var solid = false
    @ViewBuilder let items: () -> Items
    @State private var hovering = false
    @AppStorage(TextSize.key) private var textSize = TextSize.normal

    var body: some View {
        Menu {
            items()
        } label: {
            Text(name + ":")
                .font(Theme.transcript(textSize))
                .fontWeight(.semibold)
                // See-through, so the name under it shows. On hover it draws
                // itself over the shade (the shade would hide the one under it).
                .foregroundStyle(hovering || solid ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Color.clear))
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.line.opacity(hovering ? 0.9 : 0))
                        .padding(.horizontal, -3)
                }
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help("Who said this? Click to change")
        .accessibilityLabel("Speaker: \(name). Change")
    }
}

/// The ink Copy all button with an arrow for the other copies, like the
/// layout in docs/design/Main.dc.html. After copying it says "Copied 58 lines"
/// for a moment. Shortcuts live in the Transcript menu.
struct CopyButton: View {
    @Environment(RecorderModel.self) private var model
    let id: UUID
    let hasLines: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button(model.copyFeedback?.text ?? "Copy all") { model.copy(.all) }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .help(hasLines ? "Copy the whole transcript (⇧⌘C)" : "Nothing to copy yet")
            Rectangle()
                .fill(Theme.paper.opacity(0.35))
                .frame(width: 1, height: 14)
            Menu {
                Button("Copy all") { model.copy(.all) }
                Button("Copy new since last copy") { model.copy(.new) }
                Button("Copy last 10 minutes") { model.copy(.lastTenMinutes) }
                Button("Copy marked parts only") { model.copy(.marked) }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.paper)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, 4)
            .help("More ways to copy")
            .accessibilityLabel("More ways to copy")
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(Theme.paper)
        .background(Theme.ink, in: Capsule())
        .opacity(hasLines ? 1 : 0.35)
        .disabled(!hasLines)
        .fixedSize()
    }
}

/// Export as plain text or Markdown. Never overwrites a file without asking.
struct ExportMenu: View {
    @Environment(RecorderModel.self) private var model
    let hasLines: Bool

    var body: some View {
        Menu {
            Button("Plain text (.txt)…") { model.export(.text) }
            Button("Markdown (.md)…") { model.export(.markdown) }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(!hasLines)
        .help(hasLines ? "Save the transcript as a file" : "Nothing to export yet")
    }
}

/// Marks the word being heard while audio plays.
struct WordMark: TextAttribute {}

/// Draws a rounded box behind words marked with `WordMark`, then the text.
/// Boxes first, so a box never covers the edge of the letter before it.
struct WordMarkRenderer: TextRenderer {
    var color: Color

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line where run[WordMark.self] != nil {
                let rect = run.typographicBounds.rect.insetBy(dx: -3, dy: -1)
                ctx.fill(RoundedRectangle(cornerRadius: 5, style: .continuous).path(in: rect), with: .color(color))
            }
        }
        for line in layout {
            for run in line { ctx.draw(run) }
        }
    }
}

/// Margin mark (Ryan's pick, docs/design/LineLook.html): no box or fill
/// over the words, just a short pen line in the margin left of the time.
/// Grey under the pointer, blue when picked, yellow (Marker tool) or red
/// (Note tool) under the pointer with a tool on, which also sets the pointer.
/// Its own view with its own hover state, so moving the mouse redraws one
/// line and not the whole transcript.
private struct LineHighlight: ViewModifier {
    let picked: Bool
    let tool: LineTool?
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                // Left of the flag (which sits 15 pt left of the time).
                Capsule()
                    .fill(pen)
                    .frame(width: tool != nil && hovering ? 4 : 3)
                    .padding(.vertical, 3)
                    .offset(x: -24)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onHover { hovering = $0 }
            .pointerStyle(tool?.pointer ?? .default)
    }

    private var pen: Color {
        switch tool {
        case .marker?: hovering ? Theme.markPen : .clear
        case .note?: hovering ? Theme.notePen : .clear
        case nil: picked ? Theme.accent : hovering ? Theme.ink.opacity(0.22) : .clear
        }
    }
}

/// A small button on the picked line (flag, note, +). 24 pt, easy to hit.
private struct LineActionButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .background(Theme.ink.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// While a tool is on: a band at the top of the page with the tool's pen
/// color, saying what a click does, with a way to put the tool down (Esc).
private struct LineToolBand: View {
    let tool: LineTool
    let putDown: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(tool == .marker ? Theme.markPen : Theme.notePen)
                    .frame(width: 4, height: 16)
                Image(systemName: tool == .marker ? "flag.fill" : "pencil")
                    .font(.callout)
                Text(tool == .marker
                     ? "Marker tool: click lines to mark them. Click a marked line to take the flag off."
                     : "Note tool: click the line you want a note on.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Put it down", action: putDown)
                    .buttonStyle(.link)
                    .fontWeight(.medium)
                    .keyboardShortcut(.cancelAction)
                    .help("Put the tool down (Esc)")
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(Theme.paper)
            Divider()
        }
        .accessibilityElement(children: .contain)
    }
}
