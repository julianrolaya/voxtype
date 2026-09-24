# VoxType

**Offline voice dictation for macOS.** Hold a shortcut, speak, and your words appear wherever your cursor is: in email, docs, chat, code editors, or any other app. Transcription runs entirely on your Mac with [whisper.cpp](https://github.com/ggml-org/whisper.cpp). No account, no subscription, and your audio never leaves your computer.

*[Leer en español](README.es.md)*

---

## Requirements

- A Mac with **Apple Silicon** (M1 or newer)
- **macOS 14 Sonoma** or newer
- **Xcode**, free from the [App Store](https://apps.apple.com/app/id497799835). VoxType is built on your Mac from this source code, and Xcode is the tool that does it.
- About **4 GB** of free disk space

## Install

Open **Terminal** (press ⌘ Space, type *Terminal*, press Return) and paste:

```bash
git clone --recursive https://github.com/julianrolaya/voxtype.git
cd voxtype
./setup.sh
```

The installer walks you through everything, one numbered step at a time:

1. Checks that your Mac is compatible
2. Checks Xcode, and helps you finish setting it up if needed
3. Installs the one build tool it needs (`cmake`, through [Homebrew](https://brew.sh)), after asking you first
4. Builds the speech engine
5. Downloads a speech model (you choose which one) and verifies its checksum
6. *Optional:* sets up [Ollama](https://ollama.com) for local AI text cleanup
7. Builds VoxType, installs it in **Applications**, and opens the permission screen for you

You can run `./setup.sh` again at any time. Steps that are already done are skipped.

### Permissions

VoxType asks for two permissions. The installer opens the right screen for you:

| Permission | Why | How |
|---|---|---|
| **Accessibility** | To paste the text into the app you're typing in | System Settings → Privacy & Security → Accessibility → turn on **VoxType** |
| **Microphone** | To hear you | macOS asks the first time you dictate. Click **Allow**. |

## How to use it

Look for the VoxType icon in the menu bar at the top right of your screen.

- **Hold ⌥ Option + Space**, speak, and release. The text is typed where your cursor is.
- Or **tap ⌥ Space** once to start, and tap it again to stop. This is handy for longer dictation.
- While VoxType is listening, a small floating widget shows its status. You can cancel from there or copy the last result.

**Menu bar icon → Settings** lets you choose the speech model and language (Auto-detect, English or Spanish), remove filler words ("um", "eh"), and add **custom vocabulary**: names and terms the model should expect. **History** shows your recent dictations.

### Voice commands

If you say one of these on its own, VoxType performs the action instead of typing the words:

| Say | Does |
|---|---|
| "undo" / "deshacer" | ⌘Z |
| "delete" / "borrar" | Deletes the last word |
| "delete all" / "borrar todo" | Selects everything and deletes it |
| "select all" / "seleccionar todo" | ⌘A |
| "copy" / "copiar" · "paste" / "pegar" · "cut" / "cortar" | ⌘C · ⌘V · ⌘X |

## Optional: AI text cleanup

VoxType can pass what you dictate through a language model that fixes punctuation and formatting (**Formatter** mode), or that treats your dictation as a request, for example "write a polite reply declining the meeting" (**Assistant** mode).

- **Ollama (local, private).** Run `./setup.sh --ollama`, then turn it on in **Settings → Post-Processing (LLM) → Enable LLM formatting**.
- **OpenAI (cloud).** Choose *OpenAI* as the provider in the same section and paste your own API key. The key is stored in the macOS Keychain. With this option, your transcribed text is sent to OpenAI.

> AI cleanup rewrites your text. If you mix languages in one sentence, it may translate part of it. For exact transcription, leave it off.

## Update

```bash
cd voxtype
./setup.sh --update
```

After an update, macOS needs you to re-enable the Accessibility permission. The installer tells you exactly what to click.

## Change the speech model

```bash
./setup.sh --model
```

| Model | Size | Notes |
|---|---|---|
| Large V3 Turbo | ~575 MB | Recommended. Best accuracy for its size. |
| Small | ~490 MB | Lighter. A good choice for Macs with 8 GB of memory. |
| Medium | ~1.5 GB | Older, larger alternative |

Quit and reopen VoxType afterwards to load the new model.

## Uninstall

```bash
./uninstall.sh
```

This removes the app and its permissions. It asks before deleting your models, history and settings.

## Privacy

Everything runs on your Mac by default. VoxType sends nothing over the network unless you turn on the OpenAI provider. See [docs/user/privacy.md](docs/user/privacy.md) for exactly what is stored and where.

## Troubleshooting

See [docs/user/troubleshooting.md](docs/user/troubleshooting.md). Common fixes:

- **Text appears in the widget but isn't pasted.** Turn on the Accessibility permission. If it already looks on, remove VoxType from the list with **−** and add it again with **+**.
- **"VoxType needs a speech model".** Run `./setup.sh --model`.
- **The installer failed.** Run it again. It picks up where it stopped. The full log is in `build/setup.log`.

## Building manually (for developers)

```bash
git submodule update --init
cmake -S whisper.cpp -B whisper.cpp/build -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF
cmake --build whisper.cpp/build --config Release -j"$(sysctl -n hw.ncpu)"
open VoxType.xcodeproj
```

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). Builds are signed ad-hoc by default. To sign with your own certificate, create `Config/Local.xcconfig` (see `Config/Signing.xcconfig`). That also keeps the Accessibility permission across rebuilds.

## License

[MIT](LICENSE). VoxType builds on whisper.cpp and OpenAI's Whisper models. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
