#!/usr/bin/env bash

ARSENAL_VERSION="latest"

# runtime paths
export ARSENAL_ROOT="$HOME/.local/share/arsenal"
export ARSENAL_BIN="$ARSENAL_ROOT/bin"
export ARSENAL_VENDOR="$ARSENAL_ROOT/vendor"
export ARSENAL_LOCK="$ARSENAL_ROOT/arsenal.lock"
export ARSENAL_HEADER="$ARSENAL_ROOT/arsenal.h"
export ARSENAL_JSON="$ARSENAL_ROOT/ars_static.json"
export ARSENAL_PROVIDERS="$ARSENAL_ROOT/providers.txt"
export ARSENAL_LOG="$ARSENAL_ROOT/arsenal.log"
export ARSENAL_TMP="$ARSENAL_ROOT/tmp"

# local paths
export LOCAL_ROOT="$PWD/.arsenal"
export LOCAL_VENDOR="$LOCAL_ROOT/vendor"
export LOCAL_LOCK="$LOCAL_ROOT/arsenal.lock"
export LOCAL_HEADER="$LOCAL_ROOT/arsenal-local.h"

# api
export MOD_STATUS_URL="https://arsenal-api.vercel.app/api/mod_status"
export DNLD_URL="https://arsenal-api.vercel.app/api/dnld"

# create required dirs
mkdir -p "$ARSENAL_VENDOR" "$ARSENAL_TMP"
repo_to_dirname() {
    echo "$1" | tr '/' '@'
}

# get vendor path based on global flag
get_vendor_path() {
    DIRNAME=$(repo_to_dirname "$1")
    if [ "$2" = "1" ]; then
        echo "$ARSENAL_VENDOR/$DIRNAME"
    else
        echo "$LOCAL_VENDOR/$DIRNAME"
    fi
}

# get lock path based on global flag
get_lock_path() {
    if [ "$1" = "1" ]; then
        echo "$ARSENAL_LOCK"
    else
        echo "$LOCAL_LOCK"
    fi
}

# get header path based on global flag
get_header_path() {
    if [ "$1" = "1" ]; then
        echo "$ARSENAL_HEADER"
    else
        echo "$LOCAL_HEADER"
    fi
}

# source libs
ARSENAL_SRC="$(cd "$(dirname "$0")" && pwd)"
. "$ARSENAL_SRC/lock.sh"
. "$ARSENAL_SRC/utils.sh"

# internet check
net_ok() {
    curl -sf --max-time 5 --head "https://google.com" > /dev/null 2>&1 && return 0
    curl -sf --max-time 5 --head "https://cloudflare.com" > /dev/null 2>&1 && return 0
    return 1
}
# get first provider from providers.txt or fallback
get_first_provider() {
    if [ -f "$ARSENAL_PROVIDERS" ]; then
        head -1 "$ARSENAL_PROVIDERS"
    else
        echo "github.com"
    fi
}

# fetch remote mod_status
fetch_mod_status() {
    curl -sf --max-time 5 "$MOD_STATUS_URL"
}

# download and extract fresh ars_static.json
refresh_registry() {
    TMP="$ARSENAL_TMP/arsenal_static.tar.gz"
    mkdir -p "$ARSENAL_ROOT"

    curl -sf "$DNLD_URL" -o "$TMP" || {
        echo "[!] Failed to download registry"
        return 1
    }

    tar -xzf "$TMP" -C "$ARSENAL_ROOT" || {
        echo "[!] Failed to extract registry"
        return 1
    }

    return 0
}


json_lookup() {
    REPO="$1"
    [ -f "$ARSENAL_JSON" ] || return 1

    LINE=$(tail -n +2 "$ARSENAL_JSON" | grep "\"repo\":\"$REPO\"")
    [ -n "$LINE" ] || return 1

    PROVIDER=$(echo "$LINE" | sed 's/.*"provider":"\([^"]*\)".*/\1/')
    BRANCH=$(echo "$LINE"   | sed 's/.*"branch":"\([^"]*\)".*/\1/')
    LIBS=$(echo "$LINE"     | sed 's/.*"libs":"\([^"]*\)".*/\1/')

    # if no libs field set empty
    echo "$LINE" | grep -q '"libs"' || LIBS=""

    return 0
}
# search local registry
cmd_search() {
    if [ $# -ne 1 ]; then
        echo "[!] search takes exactly one keyword"
        return 1
    fi

    KEYWORD="$1"

    if [ ! -f "$ARSENAL_JSON" ]; then
        echo "[!] Registry not found, run arsenal grab first to sync"
        return 1
    fi

    echo "Results for '$KEYWORD':"
    echo ""

    COUNT=0
    TMPCOUNT="$ARSENAL_TMP/arsenal_count"
    echo 0 > "$TMPCOUNT"

    tail -n +2 "$ARSENAL_JSON" | while IFS= read -r line; do
        echo "$line" | grep -q "$KEYWORD" || continue

        REPO=$(echo "$line"     | sed 's/.*"repo":"\([^"]*\)".*/\1/')
        PROVIDER=$(echo "$line" | sed 's/.*"provider":"\([^"]*\)".*/\1/')
        BRANCH=$(echo "$line"   | sed 's/.*"branch":"\([^"]*\)".*/\1/')
        DESC=$(echo "$line"     | sed 's/.*"desc":"\([^"]*\)".*/\1/')

        printf "  repo     : %s\n" "$REPO"
        printf "  provider : %s\n" "$PROVIDER"
        printf "  branch   : %s\n" "$BRANCH"
        [ -n "$DESC" ] && printf "  desc     : %s\n" "$DESC"
        printf "\n"

        COUNT=$(cat "$TMPCOUNT")
        COUNT=$((COUNT+1))
        echo "$COUNT" > "$TMPCOUNT"
    done

    COUNT=$(cat "$TMPCOUNT")
    rm -f "$TMPCOUNT"

    [ "$COUNT" = "0" ] && echo "[~] No results found for '$KEYWORD'" \
                       || echo "[✓] $COUNT result(s) found"
}

# setup local project dirs
setup_paths() {
    GLOBAL="$1"
    if [ "$GLOBAL" = "1" ]; then
        mkdir -p "$ARSENAL_VENDOR"
    else
        mkdir -p "$LOCAL_VENDOR"
        if [ -f "$PWD/.gitignore" ]; then
            grep -qx ".arsenal" "$PWD/.gitignore" || printf "\n.arsenal\n" >> "$PWD/.gitignore"
        else
            echo ".arsenal" > "$PWD/.gitignore"
        fi
    fi
}

# main grab logic
cmd_grab() {
    GLOBAL="$1"
    shift

    if [ $# -lt 1 ]; then
        echo "[!] grab requires at least one user/repo"
        return 1
    fi

    if ! net_ok; then
        echo "[!] No internet connection, aborting"
        return 1
    fi

    setup_paths "$GLOBAL"

    REMOTE_STATUS=$(fetch_mod_status)
    if [ -z "$REMOTE_STATUS" ]; then
        echo "[!] Failed to reach registry"
        return 1
    fi

    if [ -f "$ARSENAL_JSON" ]; then
        LOCAL_STATUS=$(head -1 "$ARSENAL_JSON")
        if [ "$LOCAL_STATUS" != "$REMOTE_STATUS" ]; then
            echo "[~] Registry outdated, refreshing"
            rm -f "$ARSENAL_JSON"
            refresh_registry || return 1
        fi
    else
        echo "[~] Registry not found, downloading"
        refresh_registry || return 1
    fi

    # detect verbose
    VERBOSE=0
    for arg in "$@"; do
        [ "$arg" = "--verbose" ] && VERBOSE=1
    done

    for REPO in "$@"; do
        [ "$REPO" = "--verbose" ] && continue

        VENDOR_PATH=$(get_vendor_path "$REPO" "$GLOBAL")

        if [ -d "$VENDOR_PATH" ]; then
            echo "[~] $REPO already installed at $VENDOR_PATH"
            continue
        fi

        if json_lookup "$REPO"; then
            echo "[+] Cloning $REPO from $PROVIDER (branch: $BRANCH)"
            if [ "$VERBOSE" = "1" ]; then
                git clone -b "$BRANCH" "https://$PROVIDER/$REPO" "$VENDOR_PATH"
            else
                git clone -b "$BRANCH" "https://$PROVIDER/$REPO" "$VENDOR_PATH" \
                    > /dev/null 2>&1
            fi
        else
            echo "[~] $REPO not in registry, trying provider fallback"
            PROVIDER=$(get_first_provider)
            BRANCH="main"
            if [ "$VERBOSE" = "1" ]; then
                git clone "https://$PROVIDER/$REPO" "$VENDOR_PATH"
            else
                git clone "https://$PROVIDER/$REPO" "$VENDOR_PATH" \
                    > /dev/null 2>&1
            fi
        fi

        if [ $? -ne 0 ]; then
            echo "[!] Failed to clone $REPO"
            continue
        fi

        COMMIT=$(git -C "$VENDOR_PATH" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        DATE=$(date '+%Y-%m-%d')

        lock_add "$GLOBAL" "$REPO" "$PROVIDER" "$BRANCH" "$COMMIT" "$DATE" "$LIBS"
        headergen "$GLOBAL"

        echo "[✓] Grabbed $REPO"
    done
}

# usage
usage() {
    cat "$ARSENAL_SRC/usage.txt" 2>/dev/null || cat << EOF
usage: arsenal [-g] <command> [args...]

commands:
  grab <user/repo> [user/repo ...]     install one or more deps
  remove <user/repo> [user/repo ...]   remove one or more deps
  fix <user/repo>                      fix dep paths
  search <keyword>                     search registry
  list                                 list installed deps
  prefix                               print -I flags for compiler
  set-provider <providers...>          set git providers in order
  get-provider                         show current providers
  ch-version <user/repo> <tag/hash>    pin dep to version
  info <user/repo>                     print dep README
  cd <user/repo>                       print dep vendor path

flags:
  -g             global install
  -v/--version   print version
  -h/--help      print help
  --verbose      show git output (grab only)
EOF
}

# entry point
[ $# -lt 1 ] && usage && exit 1

case "$1" in
    --version|-v) echo "arsenal $ARSENAL_VERSION"; exit 0 ;;
    --help|-h)    usage; exit 0 ;;
esac

# check deps
for dep in git curl tar; do
    command -v "$dep" > /dev/null 2>&1 || {
        echo "[!] missing dep: $dep"
        exit 1
    }
done

# -g flag
GLOBAL=0
if [ "$1" = "-g" ]; then
    GLOBAL=1
    shift
fi

CMD="$1"
shift

case "$CMD" in
    grab)         cmd_grab "$GLOBAL" "$@" ;;
    remove)       cmd_rm "$GLOBAL" "$@" ;;
    fix)          cmd_fix "$@" ;;
    search)       cmd_search "$@" ;;
    list)         cmd_list ;;
    prefix)       cmd_prefix ;;
    set-provider) cmd_set_provider "$@" ;;
    get-provider) cmd_get_provider ;;
    ch-version)   cmd_ch_version "$@" ;;
    info)         cmd_info "$@" ;;
    cd)           cmd_cd "$@" ;;
    update) cmd_update ;;
    *)            echo "arsenal: unknown command '$CMD'"; usage; exit 1 ;;
esac
