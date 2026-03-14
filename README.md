# arsenal

A fast, minimal dependency manager for C projects. No central registry bloat — just git, curl, and a curated list of approved libraries.

```bash
arsenal grab DaveGamble/cJSON
arsenal grab rxi/log.c rxi/vec rxi/map
arsenal list
arsenal prefix
```

## Why

Every other language has a package manager. C has copy-pasting headers and hoping for the best. Arsenal fixes that.

- No central server — git hosts all files
- Curated registry at [arsenal-api.vercel.app](https://arsenal-api.vercel.app)
- Falls back to any git provider if not in registry
- Auto-generates `arsenal.h` with all your dep headers
- Local and global installs
- Tiny — four shell scripts, zero dependencies beyond git and curl

## Install

```bash
git clone https://github.com/qylvrix/arsenal
cd arsenal/src
chmod +x env.sh
./env.sh
source ~/.bashrc  # or your shell profile
```

## Usage

```bash
# install deps
arsenal grab DaveGamble/cJSON
arsenal grab rxi/log.c rxi/vec rxi/map
arsenal -g grab tezc/sc          # global install

# use in your Makefile
CFLAGS = $(shell arsenal prefix)

# or include everything at once
#include "arsenal.h"

# manage
arsenal list
arsenal search json
arsenal remove DaveGamble/cJSON
arsenal fix DaveGamble/cJSON      # force sync to latest
arsenal ch-version rxi/log.c abc1234

# providers
arsenal set-provider github.com codeberg.org
arsenal get-provider
```

## How It Works

```
arsenal grab user/repo
       ↓
checks arsenal-api.vercel.app for approved repo info
       ↓
found → clone from registry provider + branch
not found → fallback to your provider list
       ↓
clones into .arsenal/vendor/user@repo/
updates arsenal.lock
regenerates arsenal.h with all header paths
```

## File Structure

```
your-project/
├── .arsenal/
│   ├── vendor/
│   │   └── user@repo/     ← cloned dep
│   ├── arsenal.lock       ← tracks installed deps
│   └── arsenal-local.h    ← auto generated headers
└── your code
```

Global installs live at `~/.local/share/arsenal/`

## Registry

Arsenal uses a curated registry of approved C libraries. If a repo isn't in the registry arsenal falls back to cloning directly from your provider list.

Want a library added? Open an issue.

## Commands

| Command | Description |
|---|---|
| `grab <user/repo>` | Install one or more deps |
| `remove <user/repo>` | Remove one or more deps |
| `fix <user/repo>` | Force sync to latest remote |
| `search <keyword>` | Search the registry |
| `list` | List all installed deps |
| `prefix` | Print -I flags for compiler |
| `set-provider <providers>` | Set git providers in order |
| `get-provider` | Show current providers |
| `ch-version <repo> <tag>` | Pin to specific version |
| `info <user/repo>` | Print dep README |
| `cd <user/repo>` | Print vendor path |

## Flags

| Flag | Description |
|---|---|
| `-g` | Global install |
| `--verbose` | Show git output (grab only) |
| `-v` / `--version` | Print version |
| `-h` / `--help` | Print help |

## License

MIT

