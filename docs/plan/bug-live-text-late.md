# Bug: live text is late (2026-11-18)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). Preloaded live models (2026-11-19) are in `line-edit-undo.md`.

## Bugs to fix (Ryan, from real use)
- **Live text is late (2026-11-18, in class).** Words only start to show
  after a few minutes of recording, and it does not feel as live as the
  very first builds (step 4 era, about 2 s behind). Not looked at yet.
  First step next chat: ask Ryan for his ⌃⌘L paste taken while it is
  behind (it has "LIVE TEXT BEHIND THE MIC" and the stall sample), and
  which version he is on. Then compare with the old lag notes below
  (main thread stall, `SpeakerEngine.computeUnits`) before changing code.
  Fix tried the same day, branch `claude/fix-live-text-delay` (Ryan asked
  to try one before a paste). Found in code, not measured: at Start the
  speaker model loaded (and played the known voice clips), THEN Parakeet
  (and the word spotter), before any audio was handled; the audio saved
  meanwhile then went through every model and to the screen one tiny bit
  at a time (the mic gives ~47 bits a second), so the backlog cleared
  slowly. Now: `LiveQueue` (one per run) and `LiveRunner` takes all audio
  waiting at once, up to 5 s per step (`biggestBite`); Parakeet and the
  speaker model load at the same time (`async let`); "Live text is
  catching up" shows above the transcript while 4+ s wait (gone under 1
  s); ⌃⌘L has "LIVE TEXT START": seconds after Start until Parakeet
  listening, speakers listening, first words. If words are still late,
  that line says which part is slow. If "behind" keeps growing after the
  start, the models are slower than speech (look at ANE sharing between
  Parakeet, Sortformer and the word spotter), not the start.
