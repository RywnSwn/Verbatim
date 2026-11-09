# Verbatim

A Mac app that records a class, shows a live transcript, and upgrades it to
an accurate transcript in the background. Built for Ryan's English class
(Mr. Yurt), where the teacher does most of the talking.

## The user
Ryan, he/him, grade 9 student in Myanmar. He is NOT learning to code for
this: Claude writes all the code, Ryan runs the app and reports problems in
plain words. Never use em dashes in anything written for Ryan.
UX matters a lot to him. He hates apps that don't consider the user.

## Current state
Planning done, no code yet. See `PLAN.md` for build order and progress,
`docs/spec.md` for behaviour and edge cases, `DECISIONS.md` for what was
decided and why (read it before re-arguing a choice).

## Key facts
- Mac: M2, 8 GB unified memory (shared by CPU, GPU and models). Keep RAM low:
  one quantized Whisper model loaded at a time.
- Stack (confirmed): Swift + SwiftUI + WhisperKit. Minimum macOS 26.
  Ryan's Mac: Tahoe 26.7.
- Ryan does not want Xcode. Build with GitHub Actions on a macOS runner (repo
  is public for free minutes) or Command Line Tools + `swift build`.
- Claude's container is Linux and cannot run the mic or build Mac apps.
  Ryan tests on his Mac.

## Working rules
- One task per chat. At the end of each session, update `PLAN.md` (and
  `DECISIONS.md` if something was decided) so the next chat can continue.
- Keep this file short. Details go in `PLAN.md`, `DECISIONS.md`, `docs/`.
- Pin library versions. Read a library's real source/docs instead of
  guessing APIs.

## Related repo
`RywnSwn/Mr.-Yurt` is Ryan's private school log. Useful for real class
transcripts (`q2/transcripts/`) and hard names for the word list
(Nyankupon, Anansi, Kweku Tsin). Never copy school notes into this public
repo.
