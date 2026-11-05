#!/usr/bin/env bash
# Probe the LSP behaviour of a checkout of this repository.
#
# Usage:
#   tests/probe_branch.sh <repo-dir> <out-file> [probe-file]
#
# The probe deliberately runs Neovim with XDG_CONFIG_HOME pointing at a
# sandbox whose `nvim/` is a symlink to <repo-dir>. Without that, Neovim
# loads the live ~/.config/nvim, which is a DIFFERENT clone of this
# repository and would silently measure the wrong configuration.
#
# The default probe reports, for a given file type:
#   * which LSP clients are attached to a buffer of that type
#   * the merged `nvim-lspconfig` server table (enabled flags)
#
# LSP attachment is observed with a DEFERRED probe (vim.defer_fn). A
# blocking vim.wait() inside a startup command prevents the LSP client from
# ever attaching, which produces a false "server did not start" result.
set -u

REPO=$(cd "${1:?usage: probe_branch.sh <repo-dir> <out-file> [probe-file]}" && pwd -P)
OUT=${2:?usage: probe_branch.sh <repo-dir> <out-file> [probe-file]}

BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PROBE=${3:-$BASE/probe.lua}
if [ ! -f "$PROBE" ]; then
  echo "FATAL: probe not found at $PROBE" >&2
  exit 1
fi

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/lazible-probe.XXXXXX")

# Cleanup is guarded on the exact path shape mktemp produced. A bare
# `rm -rf "$SANDBOX"` on a dynamic path is one unset variable away from
# deleting something else, so the path is checked before anything is
# removed. `find -delete` is used instead of `rm -rf` because it never
# follows the `$SANDBOX/config/nvim` symlink into the repository.
#
# The retry loop is not paranoia. jdtls runs as a separate JVM that keeps
# writing into `$SANDBOX/cache/nvim/jdtls` while it shuts down, so a single
# `find -delete` pass can race it and fail with "Directory not empty". Each
# retry removes what the previous pass left behind, and the loop gives up
# after a bounded number of attempts rather than spinning forever.
cleanup() {
  case "$SANDBOX" in
    "${TMPDIR:-/tmp}"/lazible-probe.*) ;;
    *) return 0 ;;
  esac
  [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ] || return 0
  local attempt
  for attempt in $(seq 1 20); do
    find "$SANDBOX" -depth -delete 2>/dev/null
    [ -d "$SANDBOX" ] || return 0
    sleep 1
  done
  echo "WARNING: sandbox $SANDBOX was not fully removed" >&2
}
trap cleanup EXIT

mkdir -p "$SANDBOX/config"
ln -sfn "$REPO" "$SANDBOX/config/nvim"

export XDG_CONFIG_HOME="$SANDBOX/config"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="$SANDBOX/state"
export XDG_CACHE_HOME="$SANDBOX/cache"
export PATH="$XDG_DATA_HOME/nvim/mason/bin:$PATH"
mkdir -p "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

timeout 300 nvim --headless -u "$SANDBOX/config/nvim/init.lua" \
  -c "lua dofile('$PROBE')" \
  > "$OUT" 2>&1

echo "exit=$?"
