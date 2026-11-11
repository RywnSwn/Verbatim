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
Steps 1, 2, 2b, 3, 4, 5, 5c, 6, 7, 7b, 7c, 8, 9 and 11 merged, plus the in-app player and
audio shrink after Stop (5c, 6, 7, 7b, 7c, 8, 9 and 2b not fully tested by Ryan yet).
Next is step 10 (polish), mockup first. See `PLAN.md` for build order and progress,
`docs/spec.md` for behaviour, `docs/design/` for the approved layout (build
to match it), `DECISIONS.md` for what was
decided and why (read it before re-arguing a choice).

## Key facts
- Mac: M2, 8 GB unified memory (shared by CPU, GPU and models). Keep RAM low:
  one Parakeet model loaded at a time.
- Stack (confirmed): Swift + SwiftUI + FluidAudio (Parakeet, for live text
  and files). No Whisper since step 5c. Minimum macOS 26.
  Ryan's Mac: Tahoe 26.7.
- Ryan does not want Xcode. Build with GitHub Actions on a macOS runner (repo
  is public for free minutes) or Command Line Tools + `swift build`.
- Claude's container is Linux and cannot run the mic or build Mac apps.
  Ryan tests on his Mac.

## Working rules
- One task per chat. At the end of each session, update `PLAN.md` (and
  `DECISIONS.md` if something was decided) so the next chat can continue.
- Keep this file short. Details go in `PLAN.md`, `DECISIONS.md`, `docs/`.
- Tell Ryan clearly when a step is complete and when to switch to a new
  chat. Let him review before moving on. Explain every UX idea in plain
  words, and use the ux-planner skill for UI work.
- No pull requests for small things (docs, plan updates, small fixes):
  commit those straight to `main`. Only open a PR for a real milestone
  (a finished step from `PLAN.md`), or if Ryan asks. Ryan is not a dev.
- Never keep the random branch name a chat starts with (like
  `claude/inspiring-newton-...`). Name the branch after the work, e.g.
  `claude/step-3-transcribe-file`, and rename it if the work changes.
- Pin library versions. Read a library's real source/docs instead of
  guessing APIs.

## Related repo
`RywnSwn/Mr.-Yurt` is Ryan's private school log. Useful for real class
transcripts (`q2/transcripts/`) and hard names for the word list
(Nyankupon, Anansi, Kweku Tsin). Never copy school notes into this public
repo.
