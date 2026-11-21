# Step 8: the word list

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## How the word list works (step 8)
- `Model/WordList.swift`: `WordList` (words + fix rules, saved in App
  Support/Verbatim/words.json, starts with Anansi, Nyankupon, Kweku Tsin and
  the fixes Father Nazi -> Anansi, group bonds -> Nyankupon), `Fixes` (the
  text work), `WordModel` (the download).
- Boosting: FluidAudio's `StreamingUnifiedAsrManager.configureVocabularyBoosting`
  with the Parakeet CTC 110M word spotter (~100 MB, ~64 MB extra memory,
  loaded with Parakeet only while the list has words). Set in
  `ParakeetEngine.begin()`, so list changes count from the next recording or
  after Pause. An empty list reloads Parakeet (FluidAudio can't switch it off).
- The spotter's model MUST live in FluidAudio's own folder
  (App Support/FluidAudio/Models/parakeet-ctc-110m-coreml): FluidAudio reads
  its tokenizer only from there. Uninstaller trashes that folder too.
- Download order: Parakeet, speaker model, then the word spotter (only if
  the list has words). Retries every 30 s. Shown on the start screen and in
  Settings > Words.
- How fixes reach the text: the token stream is the raw text; the spotter
  rescores about every 15 s and hands back "replace X with Y"
  (`consumeVocabularyReplacements`). `LiveOutput.fixes` carries them, and
  `Fixes.applySpotted` replaces the newest match in the last 40 lines. So a
  misheard name shows for ~15 s, then fixes itself. Word times follow along.
- Fix rules: applied to the newest 2 lines every time words arrive (live and
  files), whole words, any case, punctuation kept, never on locked lines or
  the line being edited. A rule whose result contains its own left side
  ("Yurt" -> "Mr. Yurt") is not applied twice.
- After editing a line: if 1 to 4 words changed (not a single short word
  like "a", not only capitals), an inline line under it asks "Fix X to Y in
  future transcripts too? Remember / Just this once" (`RecorderModel.fixOffer`).
  Remember: saves the rule, fixes the rest of this transcript, adds the right
  side to the word list if it has a capital letter; one Undo in the bottom bar
  takes all of it back. The question goes away on the next edit or on
  switching recordings.
- Right-click a line > Add a word to word list... (name box, bottom bar confirms).
- Settings > Words: both lists, add field under each (inline reason if a
  word is too short, under 3 letters, or already there), minus button to
  remove, Undo under the lists for 10 s.
- Risks to check with Ryan: the spotter could swap a real word for a name
  that sounds close; the ~15 s delay before a name fixes itself; files
  transcribe slower with it (FluidAudio: ~26x real time, so ~2 to 3 min per hour).

## Step 8 test list for Ryan
1. After updating: start screen shows "Downloading the word list helper",
   then nothing. Settings > Words says "Listening for these words".
2. Read aloud something with Nyankupon, Anansi, Kweku Tsin (or play a class
   video): do the names come out right? Some may fix themselves after ~15 s.
3. Click a line, change one wrong word, press Enter: the line under it asks to
   remember it. Click Remember: the bottom bar says what it did. Click Undo.
4. Right-click a line > Add a word to word list..., add a name.
5. Settings > Words: remove a word, click Undo. Add a fix by hand.
6. Import a Voice Memo: how long does it take now?
7. Does any normal word get wrongly turned into a name?
