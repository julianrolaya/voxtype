# Changelog

What changed in each version of VoxType, written for the people who use it. Versions follow [Semantic Versioning](https://semver.org): before 1.0, a new feature, setting, download or permission raises the middle number (0.**2**.0), and a release with only fixes raises the last one (0.2.**1**). The format follows [Keep a Changelog](https://keepachangelog.com).

To update an existing install, run `./setup.sh --update` from your VoxType folder.

## [Unreleased]

## [0.2.0] — 2026-10-08

AI cleanup now answers in the language you spoke, VoxType no longer pastes anything when you didn't speak, and the widget stays put.

### Added

- **Voice detection before transcription.** If you press the shortcut and don't speak, nothing is pasted and the widget shows *No speech detected*. Quiet speech still gets through. `setup.sh` downloads the small voice detector this needs (under 1 MB) and verifies it like the speech model.

### Fixed

- **AI cleanup could change the language of your text.** With Ollama cleanup on, English dictation could come back in Spanish (and the other way around), and the Formatter sometimes answered a dictated question or wrote code instead of just correcting it. VoxType now tells the model which language you spoke, and the Formatter keeps your words.
- **Pressing the shortcut without speaking pasted text.** Silence or room noise could turn into phrases like "And the other.", and the Assistant would reply to them and paste the reply.
- **The widget jumped when recording started and stopped.** It no longer moves between states, no longer drifts sideways over many dictations, and opens in the right place.
- **Changing the microphone while VoxType was open could stop recording.** It now follows the new input. If the input is an empty headphone jack (for example, speakers plugged in), the notice says to check System Settings → Sound.
- Three labels in Settings were corrected.

### Changed

- With OpenAI cleanup, Settings and the privacy notes now say exactly what is sent.
- The README has screenshots of the widget and Settings, and a guide for people new to Terminal.
- **Tip:** with the default `llama3.2` model, asking the Assistant to write in a language other than the one you spoke may still answer in yours. A larger model such as `gemma4` handles it. Type the model name in Settings → Post-Processing.

## [0.1.1] — 2026-09-25

Fixes three cases where VoxType silently lost text.

### Fixed

- **Ordinary words were deleted as filler.** With filler removal on (the default), "Revisa este informe" became "Revisa informe" and "Do you know the answer" became "Do the answer". Words like *este*, *pues* and *right* are no longer treated as filler. Phrases such as "you know" or "o sea" are removed only when you set them off with commas.
- **A trailing caption credit discarded the whole dictation.** Whisper sometimes appends a line like "Subtitles by the Amara.org community". When that followed real speech, everything was thrown away and nothing was inserted. Now only that line is removed and your text is kept.
- **A filler between commas removed both commas.** "so, uh, let's wait" became "So let's wait." It now keeps one: "So, let's wait."

## [0.1.0] — 2026-09-24

First public release: offline voice dictation for macOS. Hold ⌥ Option + Space, speak, and the text appears wherever your cursor is. Transcription runs on your Mac with whisper.cpp; your audio never leaves it.

This version had two bugs that silently lost text in post-processing, fixed in 0.1.1. Use 0.1.1 or later.

[Unreleased]: https://github.com/julianrolaya/voxtype/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/julianrolaya/voxtype/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/julianrolaya/voxtype/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/julianrolaya/voxtype/releases/tag/v0.1.0
