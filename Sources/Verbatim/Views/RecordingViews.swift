import AppKit
import SwiftUI

extension RecordingInfo {
    /// "English, Mon 10 Nov"
    var fullTitle: String {
        "\(title), \(createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    /// "Started 10:05"
    var startedText: String {
        "Started \(createdAt.formatted(date: .omitted, time: .shortened))"
    }
}

/// Main area while recording. The live transcript replaces this in step 4.
struct RecordingNowView: View {
    let info: RecordingInfo

    var body: some View {
        VStack(spacing: 8) {
            Text("Live text comes in a later update.")
                .font(.title3)
            Text("For now Verbatim records the audio and saves it as you go.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(40)
        .navigationTitle(info.fullTitle)
        .navigationSubtitle(info.startedText)
    }
}

/// A finished recording. Transcripts arrive in step 3; for now you can listen to it.
struct PastRecordingView: View {
    @Environment(RecorderModel.self) private var model
    let info: RecordingInfo

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(info.fullTitle)
                    .font(.system(size: 30, weight: .medium, design: .serif))
                Text("\(info.startedText), \(RecorderModel.minutesText(info.duration))")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Play audio") {
                    NSWorkspace.shared.open(RecordingStore.audioURL(info.id))
                }
                .buttonStyle(.borderedProminent)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([RecordingStore.audioURL(info.id)])
                }
                Button("Move to Trash") { model.delete(info.id) }
            }
            Text("Transcripts come in a later update.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .navigationTitle(info.fullTitle)
        .navigationSubtitle(info.startedText)
        .toolbar {
            if !model.isBusy {
                ToolbarItem {
                    Button {
                        Task { await model.start() }
                    } label: {
                        Label("New recording", systemImage: "mic")
                    }
                    .help("Start a new recording (⌘R)")
                }
            }
        }
    }
}

/// Mic access is off. Takes over the main area, with a way out.
struct MicBlockedView: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Text("Verbatim can't hear anything")
                .font(.system(size: 30, weight: .medium, design: .serif))
            Text("Microphone access is off for Verbatim. Turn it on, then come back.")
                .foregroundStyle(.secondary)
            Button("Open Microphone settings") { model.openMicSettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(40)
    }
}
