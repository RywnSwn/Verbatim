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
Steps 1 to 11 and every PR up to RywnSwn/Verbatim#31 are merged into
`main` (latest: #27 speech model errors, #30 bug hunt 1 fixes, #31 speaker
menu, all 2026-11-21). Many are not tested by Ryan yet. See `PLAN.md` for
what's next and which test lists he hasn't run; merge history is in
`docs/plan/history.md`. `docs/spec.md` has behaviour, `docs/design/` the
approved layout (build to match it), `DECISIONS.md` what was decided and
why (read it before re-arguing a choice).

## Key facts
- Mac: M2, 8 GB unified memory (shared by CPU, GPU and models). Keep RAM low:
  one Parakeet model loaded at a time.
- Stack (confirmed): Swift + SwiftUI + FluidAudio (Parakeet, for live text
  and files). No Whisper since step 5c. Minimum macOS 26.
  Ryan's Mac: Tahoe 26.7.
- Ryan does not want Xcode. Build with GitHub Actions on a macOS runner (repo
  is public for free minutes) or Command Line Tools + `swift build`.
- Claude's container is Linux and cannot run the mic or build Mac apps.
  Ryan tests on his Mac. But the Smoke test workflow runs the app on the CI
  Mac and pushes screenshots to the `ci-smoke` branch: look at them before
  giving Ryan a build (see `PLAN.md`).

## Working rules
- Unmerged work: at the START of every chat, list remote branches with
  commits not on `main` (`git ls-remote --heads origin`, then
  `git rev-list --count origin/main..<branch>`) and tell Ryan in plain
  words. Build on the newest unmerged work it depends on, never on a
  `main` that is missing it. At the END of every chat, tell Ryan clearly
  whether the work is merged into `main` or not, and if not, which pull
  request to merge after he tests (he only merges when he asks).
- Main chat + agents (Ryan's idea, 2026-11-21): one main chat talks with
  Ryan (brainstorm, new asks, test results) and does not do big coding
  itself, except small bug fixes (a few lines, one place): the main
  chat fixes those itself (Ryan, 2026-11-21). Each feature or bigger fix
  goes to a background agent (Agent tool,
  `isolation: "worktree"`) on its own `claude/<feature>` branch, briefed
  with the `PLAN.md` section, the files, and these rules; it pushes its
  branch and never merges. The main chat checks each one (diff, CI build,
  smoke screenshots), tells Ryan in plain words what is ready and which
  test build has it, and merges only when Ryan says. At most 2 or 3
  agents at once, never two on the same files (run those one after the
  other). Each branch push makes a test build and Ryan's Mac takes the
  highest number, so say which build has what. When the main chat gets
  long, update `PLAN.md` and tell Ryan to start a new main chat.
- At the end of each session, update `PLAN.md` (and `DECISIONS.md` if
  something was decided) so the next chat can continue.
- When a task finishes, move its details from `PLAN.md` into `docs/plan/`,
  so `PLAN.md` stays short (under about 8 KB).
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
- Anything you type into (line, note, new line): only ONE thing open at a
  time, its own text box (`LineDraft` per edit), a click anywhere else only
  saves and closes it (`TypingShield`), and ⌘Z undoes it. Ryan hit a bug
  where clicking another line copied the text into it (2026-11-19).
- Pin library versions. Read a library's real source/docs instead of
  guessing APIs.

## Related repo
`RywnSwn/Mr.-Yurt` is Ryan's private school log. Useful for real class
transcripts (`q2/transcripts/`) and hard names for the word list
(Nyankupon, Anansi, Kweku Tsin). Never copy school notes into this public
repo.
