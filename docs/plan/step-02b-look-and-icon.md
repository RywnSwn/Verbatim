# Step 2b: the Notebook look and the app icon

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## How the look works (step 2b)
- Ryan compared three looks on a preview page
  (https://claude.ai/artifact/WQapwdfhQBtu6R5yFrHHuN): A Notebook, B Plain
  Mac, C Graphite. He picked A, but asked why Copy all was blue, so the
  main button is ink instead.
- `Views/Theme.swift`: colors (paper, ink, line, accent ink blue) with
  light and dark values, transcript font (New York serif 17, line spacing
  5, 14 between lines), `InkButtonStyle` (`.ink`, `.inkLarge`) for the one
  main button per screen.
- Main area and bottom bar on paper; sidebar, Settings and menus stay
  standard Mac. App tint is the ink blue (links, progress, toggles).
- Copy all sits in its own toolbar item with the glass background hidden,
  so it shows as an ink capsule.
- "Checked up to" divider in serif italic.
- Start screen animation (Ryan: it stopped abruptly): speech eases in and
  out, pauses at commas and full stops, words hold then fade, then repeat. Live text 62% ink, half-said
  words 45%.
- App icon (2026-11-20, picked by Ryan after 6 rounds, all in
  `docs/design/AppIcon.html`, live page
  https://claude.ai/artifact/36WZyRqXNNYMaz3ziksCF5): a cream printed page
  with a red satin bookmark ribbon (Note red), real paper grain, light and
  shadow. Source: `Support/AppIcon.svg`. `node scripts/make-icon.js` makes
  `Support/AppIcon.icns` (works on Linux, uses Playwright).
  `scripts/build-app.sh` copies it; Info.plist has `CFBundleIconFile`.
  Built on `claude/ux-round-2` (Ryan asked), not tested by Ryan yet.
  Test: the new icon shows in the Dock, Finder and Launchpad (if the old
  blank one sticks, drag Verbatim out of Applications and back in).
  What Ryan said no to: waveform turning into lines, anything "generic",
  busy icons with many ideas, the "Quote V" (looked like a suit), blue and
  yellow together, flat single shapes ("too blank"). What worked: ink on
  paper, made like a real object (modern skeuomorphism).
  Not done: a separate dark-mode icon (needs Xcode's new icon format).

## Step 2b test list for Ryan
1. Update, open an old transcript: serif text, warm white, ink Copy all.
2. Switch the Mac to dark mode (System Settings > Appearance): still
   easy to read? Copy all turns light.
3. Record a minute: live grey text readable? "Checked up to" line looks OK?
4. Anything that looks off or cramped: tell Claude in plain words.
