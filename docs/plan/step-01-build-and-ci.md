# Step 1: the build, CI, smoke test and test builds

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). Updates (step 11): `step-11-updates.md`.

## How the build works (step 1)
- `Package.swift`: Swift package, macOS 26, one executable target.
- `scripts/build-app.sh`: `swift build`, wraps the binary in Verbatim.app with
  `Support/Info.plist` (mic permission text), ad-hoc signs, zips. Works with
  only Command Line Tools too.
- `.github/workflows/build.yml`: every push builds on `macos-26` and creates a
  GitHub Release `v0.1.<run number>` with Verbatim.zip. Branch builds are
  marked pre-release; builds from `main` are the normal latest release.
- First open of the unsigned app: double-click, then System Settings >
  Privacy & Security > "Open Anyway" (right-click > Open no longer skips
  the warning on recent macOS).
- No auto update yet: Ryan downloads each new build by hand until step 11.
- App icon: the red Ribbon (2026-11-20), see "App icon" below.

## Smoke test on the CI Mac (2026-11-12)

NEW, use it: `.github/workflows/smoke.yml` + `scripts/ci-smoke.sh` run the
app on the CI Mac for every push to a `claude/**` branch, with fake
recordings and groups, resize the window, press ⌃⌘S, and push screenshots
to the `ci-smoke` branch (`git fetch origin ci-smoke`, then look at the
PNGs). Claude can see the real app this way. Look at the screenshots before
giving Ryan a build. Known gap: clicking a sidebar row in the script does
not open a recording yet, so only the start screen is covered.

## Cleaning branches (from "Merged to main (2026-11-12, late)")

- `claude/mini-crash-repro` is a throwaway branch: delete on GitHub.
  (2026-11-19: every `claude/*` branch is merged or throwaway; Ryan can
  prune them all. Keep `main` and `ci-smoke`.)
- Cleaning branches: Actions tab > "Delete merged branches" > Run workflow
  (`.github/workflows/prune-branches.yml`). Deletes branches with nothing
  that isn't in main and no open PR; keeps main and ci-smoke. Chats can't
  delete branches themselves (the session can only push its own branch).

## Faster builds and a lesson (2026-11-20, from UX round 2)

Faster builds (2026-11-20): Ryan hates waiting. Build 233 took 4.5 min,
about 3 of them fetching and compiling FluidAudio. Both workflows now keep
`.build` with actions/cache (key: Swift version + Package.swift hash), so
from the second build on only Verbatim compiles (about 1.5 min expected).
If a build ever fails strangely after a toolchain change, change the key.
Lesson (2026-11-20): a review subagent ran `git checkout <sha>` in the
shared checkout, so commits made meanwhile landed on a detached HEAD and
weren't pushed. Tell review agents to use `git show` / `git diff` only,
never checkout, and check `git status -sb` before pushing.
