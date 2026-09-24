#!/bin/bash
# VoxType installer — checks your Mac, builds VoxType from source, downloads a
# speech model, optionally sets up Ollama, installs the app and walks you
# through the macOS permissions it needs.
#
#   ./setup.sh             full install (safe to run again; finished steps are skipped)
#   ./setup.sh --update    pull the latest version and reinstall
#   ./setup.sh --model     only download or change the speech model
#   ./setup.sh --ollama    only set up Ollama (optional local AI text cleanup)
#   ./setup.sh --no-ollama full install without asking about Ollama
#   ./setup.sh --help

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_ID="com.voxtype.app"
APP_NAME="VoxType.app"
MODELS_DIR="$HOME/Library/Application Support/VoxType/Models"
MODEL_BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
WHISPER_DIR="$REPO_DIR/whisper.cpp"
WHISPER_STAMP="$WHISPER_DIR/build/.voxtype-built-commit"
DERIVED_DATA="$REPO_DIR/build/DerivedData"
OLLAMA_MODEL="llama3.2"
MIN_MACOS=14
MIN_FREE_GB=4
TOTAL_STEPS=7
LOG_FILE="$REPO_DIR/build/setup.log"

# ── Output helpers ──────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

step()  { echo; echo "${BOLD}${BLUE}[$1/$TOTAL_STEPS]${RESET} ${BOLD}$2${RESET}"; }
ok()    { echo "  ${GREEN}✓${RESET} $*"; }
info()  { echo "  ${DIM}$*${RESET}"; }
warn()  { echo "  ${YELLOW}!${RESET} $*"; }
fail()  {
    echo; echo "  ${RED}✗ $1${RESET}"
    shift
    for line in "$@"; do echo "    $line"; done
    echo; exit 1
}

# ask "Question?" default(y|n) — returns 0 for yes. Uses the default when not interactive.
ask() {
    local prompt="$1" default="$2" hint reply
    [[ "$default" == "y" ]] && hint="[Y/n]" || hint="[y/N]"
    if [[ ! -t 0 ]]; then [[ "$default" == "y" ]]; return; fi
    read -r -p "  $prompt $hint " reply || true
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy] ]]
}

# run_logged "what failed" cmd... — keeps compiler noise out of sight; shows it only on failure.
run_logged() {
    local what="$1"; shift
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "── $(date '+%H:%M:%S') $*" >> "$LOG_FILE"
    local start; start=$(wc -l < "$LOG_FILE")
    if ! "$@" >> "$LOG_FILE" 2>&1; then
        echo; echo "  ${RED}✗ $what${RESET}"; echo "  ${DIM}Last lines of $LOG_FILE:${RESET}"
        tail -n +"$((start + 1))" "$LOG_FILE" | grep -v 'ld: warning' | tail -n 20 | sed 's/^/    /'
        echo; echo "    Re-running ./setup.sh is safe. If it keeps failing, open an issue and attach build/setup.log."
        echo; exit 1
    fi
}

pause() {
    [[ -t 0 ]] || return 0
    read -r -p "  ${BOLD}$1${RESET} " _ || true
}

# ── 1. System ───────────────────────────────────────────────────────────────
check_system() {
    step 1 "Checking your Mac"

    [[ "$(uname -m)" == "arm64" ]] || fail "VoxType needs a Mac with Apple Silicon (M1 or newer)." \
        "This Mac reports '$(uname -m)'. whisper.cpp runs on the Apple GPU through Metal," \
        "which VoxType relies on for fast transcription."
    ok "Apple Silicon"

    local macos major
    macos="$(sw_vers -productVersion)"; major="${macos%%.*}"
    (( major >= MIN_MACOS )) || fail "VoxType needs macOS $MIN_MACOS (Sonoma) or newer. You have $macos." \
        "Update from  > System Settings > General > Software Update."
    ok "macOS $macos"

    local free_gb
    free_gb=$(( $(df -k "$HOME" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
    (( free_gb >= MIN_FREE_GB )) || fail "Not enough free disk space: ${free_gb} GB free, ${MIN_FREE_GB} GB needed." \
        "The build tools and the speech model need room. Free some space and run ./setup.sh again."
    ok "${free_gb} GB free disk space"
}

# ── 2. Xcode ────────────────────────────────────────────────────────────────
check_xcode() {
    step 2 "Checking Xcode"

    if ! xcodebuild -version >/dev/null 2>&1; then
        if [[ -d /Applications/Xcode.app ]]; then
            warn "Xcode is installed, but the command line is pointed at the Command Line Tools."
            info "Switching it to Xcode (macOS will ask for your password)…"
            sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
        else
            echo "  VoxType is built with Xcode, Apple's free developer app (a large download)."
            info "Opening Xcode in the App Store…"
            open "macappstore://apps.apple.com/app/id497799835" || true
            fail "Install Xcode, open it once, then run ./setup.sh again." \
                "(The Command Line Tools alone are not enough — VoxType needs the full Xcode.)"
        fi
    fi
    ok "$(xcodebuild -version | head -1)"

    if ! xcodebuild -license check >/dev/null 2>&1; then
        warn "The Xcode license has not been accepted yet."
        info "Showing the license (macOS will ask for your password)…"
        sudo xcodebuild -license accept
    fi
    ok "Xcode license accepted"

    if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
        info "Finishing Xcode's first-launch setup (macOS will ask for your password)…"
        sudo xcodebuild -runFirstLaunch
    fi
    ok "Xcode ready"
}

# ── 3. Build tools ──────────────────────────────────────────────────────────
load_brew() {
    if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
}

check_tools() {
    step 3 "Checking build tools"
    load_brew

    command -v git >/dev/null || fail "git is missing." "It comes with Xcode; open Xcode once and run ./setup.sh again."
    ok "git"

    if command -v cmake >/dev/null; then ok "cmake"; return; fi

    if ! command -v brew >/dev/null; then
        echo "  whisper.cpp is built with cmake, which is installed through Homebrew (brew.sh)."
        echo "  Homebrew is not installed. Its official installer is:"
        info '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        ask "Install Homebrew now?" y || fail "cmake is required." \
            "Install Homebrew from https://brew.sh (or cmake another way), then run ./setup.sh again."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        load_brew
        command -v brew >/dev/null || fail "Homebrew did not finish installing." "Follow the messages above, then run ./setup.sh again."
    fi
    ok "Homebrew"

    info "Installing cmake…"
    brew install cmake
    ok "cmake"
}

# ── 4. whisper.cpp ──────────────────────────────────────────────────────────
build_whisper() {
    step 4 "Building the speech engine (whisper.cpp)"
    cd "$REPO_DIR"

    if [[ ! -f "$WHISPER_DIR/CMakeLists.txt" ]]; then
        [[ -d "$REPO_DIR/.git" ]] || fail "The whisper.cpp folder is empty and this is not a git clone." \
            "Download VoxType with:  git clone --recursive <repository URL>"
        info "Fetching whisper.cpp…"
        git submodule update --init --recursive whisper.cpp
    fi

    local commit
    commit="$(git -C "$WHISPER_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [[ -f "$WHISPER_STAMP" && "$(cat "$WHISPER_STAMP")" == "$commit" \
          && -f "$WHISPER_DIR/build/src/libwhisper.a" ]]; then
        ok "Already built (${commit:0:7})"
        return
    fi

    info "Compiling with Metal acceleration. This takes a few minutes the first time…"
    run_logged "Configuring whisper.cpp failed." \
        cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS.0" -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF \
        -DWHISPER_BUILD_SERVER=OFF
    run_logged "Compiling whisper.cpp failed." \
        cmake --build "$WHISPER_DIR/build" --config Release -j"$(sysctl -n hw.ncpu)"
    echo "$commit" > "$WHISPER_STAMP"
    ok "whisper.cpp built (${commit:0:7})"
}

# ── 5. Speech model ─────────────────────────────────────────────────────────
expected_sha() { awk -v f="$1" '$2 == f {print $1}' "$REPO_DIR/scripts/models.sha256"; }

model_is_valid() {
    local file="$MODELS_DIR/$1"
    [[ -f "$file" ]] && [[ "$(shasum -a 256 "$file" | awk '{print $1}')" == "$(expected_sha "$1")" ]]
}

install_model() {
    step 5 "Speech model"
    mkdir -p "$MODELS_DIR"

    local installed=()
    for m in ggml-large-v3-turbo-q5_0 ggml-medium ggml-small; do
        [[ -f "$MODELS_DIR/$m.bin" ]] && installed+=("$m")
    done
    if (( ${#installed[@]} > 0 )) && [[ "${ONLY_MODEL:-0}" != 1 ]]; then
        ok "Already installed: ${installed[*]}"
        info "To change models later, run: ./setup.sh --model"
        return
    fi

    echo "  Which model should VoxType use? Every option works in English and Spanish."
    echo "    ${BOLD}1)${RESET} Large V3 Turbo  ~575 MB  ${GREEN}recommended${RESET} — best accuracy for its size"
    echo "    ${BOLD}2)${RESET} Small           ~490 MB  lighter; a good choice for 8 GB Macs"
    echo "    ${BOLD}3)${RESET} Medium          ~1.5 GB  older, larger alternative"
    local choice=1
    if [[ -t 0 ]]; then read -r -p "  Choose 1, 2 or 3 [1]: " choice || true; fi
    local name
    case "${choice:-1}" in
        2) name="ggml-small" ;;
        3) name="ggml-medium" ;;
        *) name="ggml-large-v3-turbo-q5_0" ;;
    esac
    local file="$name.bin" dest="$MODELS_DIR/$name.bin"

    if model_is_valid "$file"; then
        ok "$file is already downloaded and verified"
    else
        info "Downloading $file from Hugging Face…"
        curl -L --fail --progress-bar -C - -o "$dest.part" "$MODEL_BASE_URL/$file" \
            || fail "The download did not finish." "Check your internet connection and run ./setup.sh --model to resume."
        mv "$dest.part" "$dest"
        info "Verifying checksum…"
        model_is_valid "$file" || { rm -f "$dest"; fail "The downloaded file is corrupted (checksum mismatch)." \
            "It was deleted. Run ./setup.sh --model to download it again."; }
        ok "$file downloaded and verified"
    fi

    defaults write "$BUNDLE_ID" selectedModel "$name"
    ok "VoxType will use $name"
}

# ── 6. Ollama (optional) ────────────────────────────────────────────────────
ollama_up() { curl -s --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; }

setup_ollama() {
    step 6 "Ollama — optional AI text cleanup"
    echo "  Ollama runs a small language model on your Mac to fix punctuation and formatting"
    echo "  after you dictate. It stays offline. It is optional: VoxType works without it."
    echo "  It needs about 2 GB more disk space."
    if [[ "${ONLY_OLLAMA:-0}" != 1 ]]; then
        ask "Set up Ollama?" n || { info "Skipped. You can add it later with: ./setup.sh --ollama"; return; }
    fi

    load_brew
    if ! command -v ollama >/dev/null; then
        if command -v brew >/dev/null; then
            info "Installing Ollama…"
            brew install ollama
        else
            open "https://ollama.com/download/mac" || true
            fail "Install Ollama from https://ollama.com/download, open it once, then run ./setup.sh --ollama."
        fi
    fi
    ok "Ollama installed"

    if ! ollama_up; then
        info "Starting Ollama…"
        if [[ -d /Applications/Ollama.app ]]; then
            open -a Ollama
        elif command -v brew >/dev/null && brew list ollama >/dev/null 2>&1; then
            brew services start ollama >/dev/null
        else
            (ollama serve >/dev/null 2>&1 &)
        fi
        for _ in $(seq 1 30); do ollama_up && break; sleep 1; done
        ollama_up || fail "Ollama did not start." "Open the Ollama app (or run 'ollama serve'), then run ./setup.sh --ollama."
    fi
    ok "Ollama is running"

    info "Downloading the $OLLAMA_MODEL model…"
    ollama pull "$OLLAMA_MODEL"
    ok "$OLLAMA_MODEL ready"
    echo "  To turn it on: VoxType menu bar icon → Settings → Post-Processing (LLM) → Enable LLM formatting."
}

# ── 7. Build, install, permissions ──────────────────────────────────────────
install_app() {
    step 7 "Building and installing VoxType"
    cd "$REPO_DIR"

    local sign_args=()
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"VoxType Local"'; then
        sign_args=(CODE_SIGN_IDENTITY="VoxType Local")
        info "Signing with your local 'VoxType Local' certificate"
    fi

    info "Compiling (about a minute)…"
    run_logged "The VoxType build failed." \
        xcodebuild -project VoxType.xcodeproj -scheme VoxType -configuration Release \
        -derivedDataPath "$DERIVED_DATA" ${sign_args[@]+"${sign_args[@]}"} build -quiet

    local built="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
    [[ -d "$built" ]] || fail "Build finished, but $APP_NAME was not found at $built."

    local dest_dir="/Applications"
    [[ -w "$dest_dir" ]] || { dest_dir="$HOME/Applications"; mkdir -p "$dest_dir"; }
    INSTALLED_APP="$dest_dir/$APP_NAME"

    local was_installed=0
    [[ -d "$INSTALLED_APP" ]] && was_installed=1
    pkill -x VoxType 2>/dev/null || true
    sleep 0.5
    rm -rf "$INSTALLED_APP"
    ditto "$built" "$INSTALLED_APP"
    ok "Installed to $INSTALLED_APP"

    guide_permissions "$was_installed"
    open "$INSTALLED_APP"
}

guide_permissions() {
    local reinstall="$1"
    echo
    echo "  ${BOLD}Permissions${RESET} — VoxType needs two macOS permissions:"
    echo "    • ${BOLD}Accessibility${RESET}: to paste the text into whatever app you are typing in"
    echo "    • ${BOLD}Microphone${RESET}: macOS asks the first time you dictate — click Allow"
    echo
    if [[ "$reinstall" == 1 ]]; then
        echo "  ${YELLOW}You just replaced an earlier copy of VoxType.${RESET} macOS ties the permission to"
        echo "  the exact copy of the app, so the old entry no longer works, even if it looks on:"
        echo "    1. In the window that opens, select VoxType and remove it with the ${BOLD}−${RESET} button"
        echo "    2. Click ${BOLD}+${RESET}, choose ${BOLD}$INSTALLED_APP${RESET}, and turn it on"
    else
        echo "  In the window that opens:"
        echo "    1. Click ${BOLD}+${RESET} and choose ${BOLD}$INSTALLED_APP${RESET}"
        echo "       (if VoxType is already in the list, just turn it on)"
        echo "    2. Make sure the switch next to VoxType is ${BOLD}on${RESET}"
    fi
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true
    pause "Press Enter once VoxType is turned on…"
}

finish() {
    echo
    echo "${GREEN}${BOLD}✓ VoxType is ready.${RESET}"
    echo
    echo "  Look for the VoxType icon in the menu bar (top right of the screen)."
    echo "  ${BOLD}Hold ⌥ Option + Space${RESET}, speak, and release — the text appears where your cursor is."
    echo "  Or tap ⌥ Space once to start and tap it again to stop."
    echo
    echo "  If you see the text but it is not pasted, check the Accessibility permission."
    echo "  More help: docs/user/troubleshooting.md"
    echo
}

# ── Update ──────────────────────────────────────────────────────────────────
update() {
    cd "$REPO_DIR"
    [[ -d .git ]] || fail "--update needs a git clone of VoxType."
    [[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail "You have local changes in this folder." \
        "Commit or discard them (git stash), then run ./setup.sh --update again."
    echo "${BOLD}Updating VoxType…${RESET}"
    git pull --ff-only
    git submodule update --init --recursive whisper.cpp
}

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

# ── Main ────────────────────────────────────────────────────────────────────
MODE="full"; SKIP_OLLAMA=0
for arg in "$@"; do
    case "$arg" in
        --update)    MODE="update" ;;
        --model)     MODE="model" ;;
        --ollama)    MODE="ollama" ;;
        --no-ollama) SKIP_OLLAMA=1 ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "Unknown option: $arg"; usage; exit 1 ;;
    esac
done

echo "${BOLD}VoxType setup${RESET} ${DIM}— offline voice dictation for macOS${RESET}"

case "$MODE" in
    model)  ONLY_MODEL=1 install_model; echo; echo "  Quit and reopen VoxType to load the new model."; exit 0 ;;
    ollama) ONLY_OLLAMA=1 setup_ollama; exit 0 ;;
    update) update ;;
esac

check_system
check_xcode
check_tools
build_whisper
install_model
if [[ "$SKIP_OLLAMA" == 1 || "$MODE" == "update" ]]; then
    step 6 "Ollama — optional AI text cleanup"; info "Skipped"
else
    setup_ollama
fi
install_app
finish
