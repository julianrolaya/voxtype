#!/bin/bash
# Removes VoxType from this Mac. Asks before deleting anything beyond the app itself.
#
#   ./uninstall.sh

set -uo pipefail

BUNDLE_ID="com.voxtype.app"
SUPPORT_DIR="$HOME/Library/Application Support/VoxType"

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; GREEN=""; RESET=""
fi
ok()   { echo "  ${GREEN}✓${RESET} $*"; }
info() { echo "  ${DIM}$*${RESET}"; }
ask() {
    local reply
    [[ -t 0 ]] || return 1
    read -r -p "  $1 [y/N] " reply || true
    [[ "$reply" =~ ^[Yy] ]]
}

echo "${BOLD}Uninstalling VoxType${RESET}"
echo

pkill -x VoxType 2>/dev/null && ok "Quit VoxType"

removed_app=0
for app in "/Applications/VoxType.app" "$HOME/Applications/VoxType.app"; do
    if [[ -d "$app" ]]; then
        rm -rf "$app" && ok "Removed $app" && removed_app=1
    fi
done
(( removed_app )) || info "VoxType.app was not found in Applications"

tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 && ok "Removed the Accessibility permission"
tccutil reset Microphone "$BUNDLE_ID" >/dev/null 2>&1 && ok "Removed the Microphone permission"

echo
if [[ -d "$SUPPORT_DIR" ]]; then
    size="$(du -sh "$SUPPORT_DIR" 2>/dev/null | awk '{print $1}')"
    echo "  $SUPPORT_DIR ($size) holds the speech models"
    echo "  and your dictation history."
    if ask "Delete them?"; then
        rm -rf "$SUPPORT_DIR" && ok "Deleted models and history"
    else
        info "Kept"
    fi
fi

if defaults read "$BUNDLE_ID" >/dev/null 2>&1 || security find-generic-password -s "$BUNDLE_ID" >/dev/null 2>&1; then
    if ask "Delete your VoxType settings and the saved OpenAI key, if any?"; then
        defaults delete "$BUNDLE_ID" >/dev/null 2>&1
        while security delete-generic-password -s "$BUNDLE_ID" >/dev/null 2>&1; do :; done
        ok "Deleted settings and saved key"
    else
        info "Kept"
    fi
fi

echo
echo "${GREEN}${BOLD}✓ Done.${RESET}"
if command -v ollama >/dev/null 2>&1; then
    echo
    info "Ollama is still installed; VoxType does not remove it because other apps may use it."
    info "To remove the model VoxType used:  ollama rm llama3.2"
fi
info "You can delete this folder (the VoxType source code) whenever you like."
