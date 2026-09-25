# Troubleshooting

Start here: **running `./setup.sh` again is always safe.** It skips what is already done and repairs what isn't. If a step fails, the full log is in `build/setup.log`.

## Installing

**"VoxType needs the full Xcode"** — The Command Line Tools alone can't build a Mac app. Install [Xcode](https://apps.apple.com/app/id497799835) from the App Store, open it once, then run `./setup.sh` again.

**It asks for my password** — Only for Xcode's one-time setup (accepting its license, finishing its first launch) and, if you agree, for installing Homebrew. Type your Mac login password. Nothing appears on screen while you type; that's normal.

**A window asks to install "command line developer tools"** — macOS asks this the first time you use `git`. Click **Install**, wait until it says it finished, then paste the installation lines again.

**"No such file or directory" or "command not found: ./setup.sh"** — Terminal isn't inside the VoxType folder. Type `cd voxtype`, press Return, and run `./setup.sh` again. If you cloned it somewhere other than your home folder, type `cd ` (with a space after it) and drag the VoxType folder into the Terminal window before pressing Return.

**I downloaded the "Source code" zip and the installer fails** — The zip leaves out the speech engine, which is a git submodule, and a zip is not a git repository, so the missing part can't be fetched afterwards. Delete it and follow the [Install](../../README.md#install) steps, which use `git clone --recursive`.

**"The whisper.cpp folder is empty"** — The project was downloaded without its speech engine. Run `git submodule update --init` inside the folder, or clone again with `git clone --recursive`.

**The model download stopped** — Run `./setup.sh --model`. The download resumes where it stopped, and every file is checked against a known checksum before use.

**"Apple Silicon" or "macOS 14" check fails** — VoxType relies on the Apple GPU (Metal) and on APIs from macOS 14. Intel Macs and older macOS versions aren't supported.

## Using VoxType

**Nothing happens when I press ⌥ Space**
1. Check that the VoxType icon is in the menu bar. If it isn't, open VoxType from Applications.
2. Another app may already use ⌥ Space (some launchers and input-source switchers do). Quit it or change its shortcut.
3. If the icon says *Loading model…*, wait a few seconds. The first load after starting takes the longest.

**The text shows in the widget but is not pasted**
VoxType needs the **Accessibility** permission to paste.
1. Open System Settings → Privacy & Security → Accessibility.
2. If VoxType is in the list, select it and remove it with **−**. (After an update, the old entry stops working even though it still looks on.)
3. Click **+**, choose **Applications → VoxType**, and turn it on.
4. Quit VoxType from its menu and open it again.

**It never hears me / the widget doesn't appear**
Check System Settings → Privacy & Security → **Microphone** and make sure VoxType is on. Also check that the right microphone is selected in System Settings → Sound → Input.

**"VoxType needs a speech model"** — Run `./setup.sh --model`, then quit and reopen VoxType.

**Words come out wrong** — In Settings, set the language to the one you're speaking instead of Auto-detect, and add names or technical terms to **Custom Vocabulary**. If you use AI cleanup, try turning it off: it rewrites text and can translate mixed-language sentences.

**The first word or two gets cut off** — Turn on **Settings → Keep microphone ready**. VoxType then keeps the microphone open between dictations, so it's ready the instant you press the shortcut. macOS shows the orange microphone indicator while it's on.

## AI cleanup (Ollama)

**Ollama isn't connecting** — Make sure Ollama is running: open the Ollama app, or run `ollama serve` in Terminal. Then check that the model name in Settings matches one you've downloaded (`ollama list`). Run `./setup.sh --ollama` to set it up again.

## Still stuck?

Open an issue on GitHub. Describe what you did, what you expected and what happened, and attach `build/setup.log` if the problem is with installing.
