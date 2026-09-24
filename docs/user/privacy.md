# Privacy

VoxType is built to work without the internet. Here is exactly what it does with your data.

## What stays on your Mac

| What | Where | Details |
|---|---|---|
| Your voice | Memory only | Audio is transcribed and then discarded. It is never saved to disk. |
| Dictation history | `~/Library/Application Support/VoxType/history.json` | Your last 50 dictations. Delete them from **History → Clear All**. |
| Speech models | `~/Library/Application Support/VoxType/Models/` | Downloaded once by `setup.sh`. |
| Settings | macOS preferences (`com.voxtype.app`) | Model, language, vocabulary, widget options. |
| OpenAI API key | macOS Keychain | Only if you enter one. It is never stored in plain text. |
| Timing log | `~/Library/Application Support/VoxType/perf.jsonl` | **Off by default.** It records timings and character counts, never your text. |

## The clipboard

To type into any app, VoxType places the text on the clipboard, presses ⌘V for you, and puts your previous clipboard contents back about half a second later. If you use a clipboard manager, it may record your dictations.

## What goes over the network

- **By default: nothing.** Transcription and the optional Ollama cleanup both run locally. Ollama listens only on `localhost`.
- **Only if you choose OpenAI** as the AI cleanup provider: the transcribed text (not your audio) is sent to OpenAI's API over HTTPS, under [OpenAI's terms](https://openai.com/policies).
- `setup.sh` downloads the speech model from Hugging Face and, if you ask for it, installs Homebrew, cmake and Ollama. The VoxType app itself does not download anything.

VoxType has no analytics, telemetry or crash reporting.

## Removing everything

Run `./uninstall.sh`. It asks before deleting your history, models, settings and saved key.
