#!/usr/bin/env bash

ARSENAL_ROOT="$HOME/.local/share/arsenal"
ARSENAL_BIN="$ARSENAL_ROOT/bin"

find_profile() {
    for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" \
             "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.kshrc" \
             "$HOME/.config/fish/config.fish"; do
        [ -f "$f" ] && echo "$f" && return
    done
    echo "$HOME/.profile"
}

add_to_path() {
    PROFILE=$(find_profile)
    grep -q "$ARSENAL_BIN" "$PROFILE" 2>/dev/null && return 0
    printf "\n# arsenal\nexport PATH=\"\$PATH:%s\"\n" "$ARSENAL_BIN" >> "$PROFILE"
    echo "[✓] Added arsenal to PATH in $PROFILE"
    echo "[~] Restart shell or run: source $PROFILE"
}

install_arsenal() {
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    mkdir -p "$ARSENAL_BIN"

    for f in arsenal.sh lock.sh utils.sh usage.txt; do
        if [ -f "$SCRIPT_DIR/$f" ]; then
            cp "$SCRIPT_DIR/$f" "$ARSENAL_BIN/$f"
            chmod +x "$ARSENAL_BIN/$f"
            echo "[✓] Installed $f"
        else
            echo "[!] Missing $f skipping"
        fi
    done

    ln -sf "$ARSENAL_BIN/arsenal.sh" "$ARSENAL_BIN/arsenal"
    chmod +x "$ARSENAL_BIN/arsenal"

    add_to_path
    echo "[✓] Arsenal installed to $ARSENAL_BIN"
}

install_arsenal
