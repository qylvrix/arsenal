#!/usr/bin/env bash

# remove a dep
cmd_rm() {
    GLOBAL="$1"
    shift

    if [ $# -lt 1 ]; then
        echo "[!] remove requires at least one user/repo"
        return 1
    fi

    for REPO in "$@"; do
        VENDOR_PATH=$(get_vendor_path "$REPO" "$GLOBAL")

        if [ ! -d "$VENDOR_PATH" ]; then
            # try other scope if not found
            if [ "$GLOBAL" = "1" ]; then
                VENDOR_PATH=$(get_vendor_path "$REPO" "0")
            else
                VENDOR_PATH=$(get_vendor_path "$REPO" "1")
            fi
        fi

        if [ ! -d "$VENDOR_PATH" ]; then
            echo "[!] $REPO not found in local or global installs"
            continue
        fi

        printf "[~] Removing %s, this cannot be undone\n" "$REPO"
        rm -rf "$VENDOR_PATH"

        # determine which scope it was in
        if echo "$VENDOR_PATH" | grep -q "$ARSENAL_VENDOR"; then
            lock_remove "1" "$REPO"
            headergen "1"
        else
            lock_remove "0" "$REPO"
            headergen "0"
        fi

        echo "[✓] Removed $REPO"
    done
}

# force sync repo to latest remote
cmd_fix() {
    if [ $# -ne 1 ]; then
        echo "[!] fix takes exactly one user/repo"
        return 1
    fi

    REPO="$1"

    # find where repo lives
    VENDOR_PATH=$(get_vendor_path "$REPO" "0")
    GLOBAL="0"
    if [ ! -d "$VENDOR_PATH" ]; then
        VENDOR_PATH=$(get_vendor_path "$REPO" "1")
        GLOBAL="1"
    fi

    if [ ! -d "$VENDOR_PATH" ]; then
        echo "[!] $REPO not found in local or global installs"
        return 1
    fi

    printf "[~] Force syncing %s\n" "$REPO"

    # fetch all
    git -C "$VENDOR_PATH" fetch --all > /dev/null 2>&1 || {
        echo "[!] Failed to fetch $REPO"
        return 1
    }

    # get current branch
    BRANCH=$(git -C "$VENDOR_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)
    BRANCH=${BRANCH:-main}

    # hard reset
    git -C "$VENDOR_PATH" reset --hard "origin/$BRANCH" > /dev/null 2>&1 || {
        echo "[!] Failed to reset $REPO"
        return 1
    }

    # clean untracked
    git -C "$VENDOR_PATH" clean -fd > /dev/null 2>&1 || {
        echo "[!] Failed to clean $REPO"
        return 1
    }

    headergen "$GLOBAL"
    echo "[✓] Reset $REPO to latest remote"
}

# list all installed deps
cmd_list() {
    FOUND=0

    for GLOBAL in 0 1; do
        LOCK=$(get_lock_path "$GLOBAL")
        [ -f "$LOCK" ] || continue

        LABEL="local"
        [ "$GLOBAL" = "1" ] && LABEL="global"

        # parse lock file blocks
        REPO=""
        while IFS= read -r line; do
            case "$line" in
                \[*\])
                    REPO="${line#[}"
                    REPO="${REPO%]}"
                    printf "\n  [%s] (%s)\n" "$REPO" "$LABEL"
                    FOUND=1
                    ;;
                provider=*) printf "    provider : %s\n" "${line#provider=}" ;;
                branch=*)   printf "    branch   : %s\n" "${line#branch=}" ;;
                commit=*)   printf "    commit   : %s\n" "${line#commit=}" ;;
                date=*)     printf "    date     : %s\n" "${line#date=}" ;;
            esac
        done < "$LOCK"
    done

    [ "$FOUND" = "0" ] && echo "[~] No packages installed"
}

# print -I flags for all installed deps
cmd_prefix() {
    FOUND=0

    for GLOBAL in 0 1; do
        if [ "$GLOBAL" = "1" ]; then
            VENDOR="$ARSENAL_VENDOR"
        else
            VENDOR="$LOCAL_VENDOR"
        fi

        [ -d "$VENDOR" ] || continue

        for repo_dir in "$VENDOR"/*/; do
            [ -d "$repo_dir" ] || continue
            ABSPATH=$(cd "$repo_dir" && pwd)
            printf -- "-I%s " "$ABSPATH"
            FOUND=1
        done
    done

    [ "$FOUND" = "1" ] && printf "\n" || echo "[~] No packages installed"
}

# set providers in priority order
cmd_set_provider() {
    if [ $# -lt 1 ]; then
        echo "[!] set-provider requires at least one provider"
        return 1
    fi

    mkdir -p "$(dirname "$ARSENAL_PROVIDERS")"
    > "$ARSENAL_PROVIDERS"

    i=1
    for PROVIDER in "$@"; do
        echo "$PROVIDER" >> "$ARSENAL_PROVIDERS"
        printf "  %d. %s\n" "$i" "$PROVIDER"
        i=$((i+1))
    done

    echo "[✓] Providers updated"
}

# print current providers
cmd_get_provider() {
    if [ ! -f "$ARSENAL_PROVIDERS" ]; then
        echo "[~] No providers set, default is github.com"
        return 0
    fi

    echo "Providers (in priority order):"
    i=1
    while IFS= read -r line; do
        [ -n "$line" ] && printf "  %d. %s\n" "$i" "$line"
        i=$((i+1))
    done < "$ARSENAL_PROVIDERS"
}

# change pinned version
cmd_ch_version() {
    if [ $# -ne 2 ]; then
        echo "[!] ch-version takes exactly user/repo and tag/hash"
        return 1
    fi

    REPO="$1"
    VERSION="$2"

    # try local then global
    for GLOBAL in 0 1; do
        LOCK=$(get_lock_path "$GLOBAL")
        [ -f "$LOCK" ] || continue
        grep -q "^\[$REPO\]" "$LOCK" || continue
        lock_ch_version "$GLOBAL" "$REPO" "$VERSION"
        return 0
    done

    echo "[!] $REPO not found in any lock file"
    return 1
}

# print vendor path of repo
cmd_cd() {
    if [ $# -ne 1 ]; then
        echo "[!] cd takes exactly one user/repo"
        return 1
    fi

    REPO="$1"

    for GLOBAL in 0 1; do
        VENDOR_PATH=$(get_vendor_path "$REPO" "$GLOBAL")
        [ -d "$VENDOR_PATH" ] || continue
        ABSPATH=$(cd "$VENDOR_PATH" && pwd)
        echo "$ABSPATH"
        return 0
    done

    echo "[!] $REPO not found in local or global installs"
    return 1
}

# print README of repo
cmd_info() {
    if [ $# -ne 1 ]; then
        echo "[!] info takes exactly one user/repo"
        return 1
    fi

    REPO="$1"

    for GLOBAL in 0 1; do
        VENDOR_PATH=$(get_vendor_path "$REPO" "$GLOBAL")
        [ -d "$VENDOR_PATH" ] || continue

        for readme in README.md readme.md README readme; do
            [ -f "$VENDOR_PATH/$readme" ] || continue
            cat "$VENDOR_PATH/$readme"
            return 0
        done

        echo "[!] No README found for $REPO"
        return 1
    done

    echo "[!] $REPO not found in local or global installs"
    return 1
}
