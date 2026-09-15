#!/usr/bin/env bash
# bb-toolkit installer — builds a self-contained hunting environment under $BB.
#
#   ./install.sh                 everything (tools + templates + wordlists)
#   ./install.sh --minimal       tools + nuclei templates, skip the 1GB wordlists
#   ./install.sh --tools-only    just the binaries
#   ./install.sh --ipv4          force IPv4 (some ISPs advertise broken IPv6)
#
# No sudo. Nothing is written outside this folder except a ~/.gf symlink,
# which is the only path the `gf` tool will read.
set -uo pipefail

BB="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
GO_VERSION="1.23.4"
MINIMAL=0; TOOLS_ONLY=0; CURL_OPTS=(-sSL --retry 10 --retry-all-errors --retry-delay 3)

while [ $# -gt 0 ]; do
  case "$1" in
    --minimal)    MINIMAL=1;;
    --tools-only) TOOLS_ONLY=1; MINIMAL=1;;
    --ipv4)       CURL_OPTS+=(-4);;
    -h|--help)    sed -n '2,10p' "$0" | sed 's/^# \?//'; exit 0;;
    *) echo "unknown option: $1"; exit 1;;
  esac; shift
done

ok(){   printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[1;33m!\033[0m %s\n' "$*"; }
die(){  printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
say(){  printf '\n\033[1;36m==>\033[0m \033[1m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- prereqs
say "checking prerequisites"
for c in curl git python3 tar; do
  command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
done
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)' \
  || die "python3 >= 3.8 required"
ok "curl git python3 tar"

mkdir -p "$BB"/{bin,opt,tools,data/{configs/tools,templates,resolvers},wordlists,targets,loot,notes,logs}

# ------------------------------------------------------------ go toolchain
say "go toolchain"
export GOROOT="$BB/opt/go" GOPATH="$BB/opt/gopath" GOBIN="$BB/bin"
export GOMODCACHE="$GOPATH/pkg/mod" GOCACHE="$BB/opt/cache/go-build"
export PATH="$GOROOT/bin:$BB/bin:$PATH"

if [ -x "$GOROOT/bin/go" ]; then
  ok "already present ($("$GOROOT/bin/go" version | awk '{print $3}'))"
else
  case "$(uname -m)" in
    x86_64|amd64) GOARCH=amd64;; aarch64|arm64) GOARCH=arm64;;
    *) die "unsupported arch: $(uname -m)";;
  esac
  echo "  downloading go${GO_VERSION}.linux-${GOARCH}..."
  curl "${CURL_OPTS[@]}" -C - -o "$BB/opt/go.tar.gz" \
    "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" || die "go download failed"
  tar -C "$BB/opt" -xzf "$BB/opt/go.tar.gz" && rm -f "$BB/opt/go.tar.gz"
  ok "installed $("$GOROOT/bin/go" version | awk '{print $3}')"
fi

# ---------------------------------------------------------------- go tools
say "go tools ($(grep -cvE '^\s*(#|$)' "$BB/go-tools.txt") packages — this takes a while)"
FAILED=()
while read -r pkg; do
  case "$pkg" in ''|\#*) continue;; esac
  n=$(basename "${pkg%@*}")
  [ -x "$BB/bin/$n" ] && { ok "$n (cached)"; continue; }
  printf '  … %-20s' "$n"
  if GOFLAGS=-mod=mod go install "$pkg" >>"$BB/logs/install-go.log" 2>&1; then
    printf '\r'; ok "$n                 "
  else
    printf '\r'; warn "$n — FAILED (see logs/install-go.log)"; FAILED+=("$n")
  fi
done < "$BB/go-tools.txt"

# ------------------------------------------------------------ python tools
say "python tools"
export PIPX_HOME="$BB/opt/pipx" PIPX_BIN_DIR="$BB/bin"
if ! command -v pipx >/dev/null 2>&1; then
  python3 -m pip install --user --quiet pipx >/dev/null 2>&1 \
    || warn "could not install pipx — skipping pip-based tools"
fi
if command -v pipx >/dev/null 2>&1; then
  for p in arjun uro wafw00f dirsearch apkleaks; do
    [ -x "$BB/bin/$p" ] && { ok "$p (cached)"; continue; }
    printf '  … %-20s' "$p"
    if pipx install "$p" >>"$BB/logs/install-py.log" 2>&1; then
      printf '\r'; ok "$p                 "
    else
      printf '\r'; warn "$p — FAILED"
    fi
  done
else
  warn "pipx unavailable"
fi

# ------------------------------------- git-cloned tools + generated wrappers
say "git-cloned tools"
clone(){ # clone <dir> <repo>
  if [ -d "$BB/tools/$1/.git" ]; then
    git -C "$BB/tools/$1" pull -q 2>/dev/null; ok "$1 (updated)"
  else
    git clone -q --depth 1 "$2" "$BB/tools/$1" 2>/dev/null \
      && ok "$1" || warn "$1 — clone failed"
  fi
}
wrap(){ # wrap <name> <relative-script>
  cat > "$BB/bin/$1" <<WRAP
#!/usr/bin/env bash
exec python3 "\$(dirname "\$(readlink -f "\$0")")/../tools/$2" "\$@"
WRAP
  chmod +x "$BB/bin/$1"
}

clone gf-patterns   https://github.com/tomnomnom/gf
clone xsstrike      https://github.com/s0md3v/XSStrike
clone linkfinder    https://github.com/GerbenJavado/LinkFinder
clone secretfinder  https://github.com/m4ll0k/SecretFinder
clone paramspider   https://github.com/devanshbatham/ParamSpider
clone corsy         https://github.com/s0md3v/Corsy
clone jwt_tool      https://github.com/ticarpi/jwt_tool

wrap xsstrike     xsstrike/xsstrike.py
wrap linkfinder   linkfinder/linkfinder.py
wrap secretfinder secretfinder/SecretFinder.py
wrap corsy        corsy/corsy.py
wrap jwt_tool     jwt_tool/jwt_tool.py

# gf reads ~/.gf and nothing else — symlink it into $BB so patterns stay in-folder
mkdir -p "$BB/data/configs/gf"
cp -n "$BB"/tools/gf-patterns/examples/*.json "$BB/data/configs/gf/" 2>/dev/null
ln -sfn "$BB/data/configs/gf" "$HOME/.gf"
ok "gf patterns -> ~/.gf symlink"

# ------------------------------------------------------------------ massdns
# puredns is useless without it and it ships no binary — must be compiled.
say "massdns (compiled from source — puredns depends on it)"
if [ -x "$BB/bin/massdns" ]; then
  ok "already built"
elif ! command -v make >/dev/null 2>&1 || ! command -v gcc >/dev/null 2>&1; then
  warn "gcc/make not found — skipping. bb-brute will not work until massdns is built."
else
  clone massdns https://github.com/blechschmidt/massdns
  if make -C "$BB/tools/massdns" >>"$BB/logs/install-massdns.log" 2>&1; then
    cp "$BB/tools/massdns/bin/massdns" "$BB/bin/massdns" && ok "built"
  else
    warn "build failed (see logs/install-massdns.log)"
  fi
fi

# -------------------------------------------------- templates and resolvers
if [ "$TOOLS_ONLY" = 0 ]; then
  say "nuclei templates"
  # nuclei's own -update-templates silently no-ops in a relocated install;
  # fetch the tarball directly instead.
  mkdir -p "$BB/data/templates" && cd "$BB/data/templates"
  if curl "${CURL_OPTS[@]}" -C - -o nt.tar.gz \
      "https://codeload.github.com/projectdiscovery/nuclei-templates/tar.gz/refs/heads/main"; then
    rm -rf nuclei-templates && tar -xzf nt.tar.gz \
      && mv nuclei-templates-main nuclei-templates && rm -f nt.tar.gz
    ok "$(find nuclei-templates -name '*.yaml' | wc -l) templates"
  else
    warn "template download failed"
  fi
  cd "$BB"

  say "resolvers"
  curl "${CURL_OPTS[@]}" -o "$BB/data/resolvers/resolvers.txt" \
    https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt \
    && ok "$(wc -l < "$BB/data/resolvers/resolvers.txt") resolvers" \
    || warn "resolver download failed"
fi

# ---------------------------------------------------------------- wordlists
if [ "$MINIMAL" = 0 ]; then
  say "wordlists (SecLists, ~1GB — skip with --minimal)"
  if [ -d "$BB/wordlists/seclists/.git" ]; then
    git -C "$BB/wordlists/seclists" pull -q 2>/dev/null; ok "seclists (updated)"
  else
    # git clone dies on repos this size over flaky links; tarball resumes.
    curl "${CURL_OPTS[@]}" -C - -o "$BB/wordlists/sl.tar.gz" \
      "https://codeload.github.com/danielmiessler/SecLists/tar.gz/refs/heads/master" \
      && tar -C "$BB/wordlists" -xzf "$BB/wordlists/sl.tar.gz" \
      && mv "$BB/wordlists/SecLists-master" "$BB/wordlists/seclists" \
      && rm -f "$BB/wordlists/sl.tar.gz" && ok "seclists" || warn "seclists download failed"
  fi
  say "bruteforce wordlist (trickest inventory, used by bb-brute --depth max)"
  curl "${CURL_OPTS[@]}" -o "$BB/wordlists/seclists/Discovery/DNS/bug-bounty-program-subdomains-trickest-inventory.txt" \
    "https://raw.githubusercontent.com/trickest/wordlists/main/inventory/subdomains.txt" \
    && ok "trickest inventory" || warn "trickest wordlist failed (bb-brute --depth max unavailable)"
fi

chmod +x "$BB"/scripts/* 2>/dev/null

# ------------------------------------------------------------------- report
say "done"
echo "  binaries in \$BB/bin: $(ls "$BB/bin" 2>/dev/null | wc -l)"
[ ${#FAILED[@]} -gt 0 ] && warn "failed go tools: ${FAILED[*]}"
cat <<NEXT

  Activate:      source $BB/env.sh
  Permanent:     echo 'source $BB/env.sh' >> ~/.bashrc

  Then:          bb-new acme acme.com
                 \$EDITOR \$TARGETS/acme/scope/out-of-scope.txt   # from the policy
                 bb-hunt acme --no-discord

  Read docs/METHODOLOGY.md before pointing any of this at a real target.
NEXT
