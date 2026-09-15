#!/usr/bin/env bash
# bb-toolkit environment — source this:  source /path/to/bb-toolkit/env.sh
#
# Everything (binaries, Go module cache, Python venvs, wordlists, tool config)
# lives under $BB. Nothing is installed system-wide, nothing needs sudo, and
# deleting the folder removes the whole environment.

# $BB is wherever this file lives, so the checkout is relocatable.
_bb_src="${BASH_SOURCE[0]:-$0}"
export BB="$(cd "$(dirname "$(readlink -f "$_bb_src")")" && pwd)"
unset _bb_src

# --- Go toolchain (self-contained) ---
export GOROOT="$BB/opt/go"
export GOPATH="$BB/opt/gopath"
export GOBIN="$BB/bin"
export GOMODCACHE="$BB/opt/gopath/pkg/mod"
export GOCACHE="$BB/opt/cache/go-build"

# --- Python (pipx isolated, redirected into $BB) ---
export PIPX_HOME="$BB/opt/pipx"
export PIPX_BIN_DIR="$BB/bin"

# --- Tool config/state kept in-folder, not in $HOME ---
export PDCP_HOME="$BB/data/configs/pdcp"          # ProjectDiscovery cloud config
export NUCLEI_TEMPLATES="$BB/data/templates/nuclei-templates"
export GF_PATH="$BB/data/configs/gf"
# gf ignores $GF_PATH and only ever reads ~/.gf — keep it a symlink into $BB.
[ -L "$HOME/.gf" ] || ln -sfn "$GF_PATH" "$HOME/.gf" 2>/dev/null
export WORDLISTS="$BB/wordlists"
export SECLISTS="$BB/wordlists/seclists"
export RESOLVERS="$BB/data/resolvers/resolvers.txt"
export TARGETS="$BB/targets"
export LOOT="$BB/loot"
export NOTES="$BB/notes"

# --- PATH ---
export PATH="$BB/bin:$GOROOT/bin:$BB/scripts:$PATH"

# --- Quality of life ---
alias bb='cd $BB'
alias bbt='cd $TARGETS'
alias bbn='cd $NOTES'
alias bbl='cd $LOOT'

# jump to (or create) a program workspace:  prog acme.com
prog() { mkdir -p "$TARGETS/$1"/{scope,recon,urls,scans,screenshots,loot,notes,state} && cd "$TARGETS/$1"; }

echo "[bb] env loaded -> $BB  (bin: $(ls "$BB/bin" 2>/dev/null | wc -l) tools)"
