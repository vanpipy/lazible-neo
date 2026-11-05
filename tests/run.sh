#!/usr/bin/env bash
# Run the mini.test harness against this repository's real config.
#
# The suite drives a headless Neovim that loads the repo's own
# lua/config/lazy.lua, so the keymaps and plugin wiring under test are the
# ones a user actually gets.
#
# Usage:
#   tests/run.sh                          # the whole suite
#   tests/run.sh tests/suites/smoke.lua   # a single file
#
# The mini.nvim dependency (which provides mini.test) is bootstrapped into
# tests/.deps/ on first run and pinned to the commit in tests/mini.lock.
# Nothing outside the repo is written to.
set -u

BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$BASE/.." && pwd)

# The plugin store to test against. This is the real one, so the harness
# exercises the plugins the user has installed. Nothing is installed or
# updated by a run.
DATA=${XDG_DATA_HOME:-$HOME/.local/share}

MINI_URL=https://github.com/nvim-mini/mini.nvim
MINI_PIN=$(cat "$BASE/mini.lock")

# Bootstrap mini.nvim.
#
# mini.nvim is a single upstream repository that provides every `mini.*`
# module, including `mini.test`. The individual `mini.ai`, `mini.pairs` and
# friends that LazyVim installs are separate repositories and do NOT contain
# mini.test, so the harness needs this one specifically.
DEPS="$BASE/.deps"
MINI_DIR="$DEPS/mini.nvim"

if [ ! -d "$MINI_DIR/.git" ]; then
  echo "bootstrapping mini.nvim into $MINI_DIR ..."
  # Delete through `find -delete` rather than `rm -rf`. The path is derived
  # from this script's own location, but it is still a dynamic path, and
  # `find -delete` never follows a symlink out of the tree it is given.
  find "$MINI_DIR" -depth -delete 2>/dev/null
  mkdir -p "$DEPS"
  git clone --filter=blob:none "$MINI_URL" "$MINI_DIR" >/dev/null 2>&1 || {
    echo "FATAL: could not clone $MINI_URL" >&2
    exit 1
  }
fi

# Check out the pinned commit, so the suite is reproducible.
if [ "$(git -C "$MINI_DIR" rev-parse HEAD)" != "$MINI_PIN" ]; then
  echo "checking out pinned mini.nvim $MINI_PIN ..."
  git -C "$MINI_DIR" checkout --quiet "$MINI_PIN" || {
    echo "FATAL: could not check out $MINI_PIN" >&2
    exit 1
  }
fi

# Sandbox config dir. `nvim` inside it must be a symlink to the repo.
#
# This is what makes the harness test the repo. Neovim resolves
# stdpath("config") from XDG_CONFIG_HOME, and LazyVim reads
# stdpath("config") .. "/lazyvim.json" to decide which extras to load.
# Without the symlink, the harness silently loads the live ~/.config/nvim
# (a different clone) and validates the wrong configuration entirely.
#
# The link has to be recreated from scratch every run. `ln -sfn` on an
# existing *directory* creates the link inside that directory instead of
# replacing it, which once left the harness loading a stale copy of the repo.
SANDBOX_CONFIG="$DEPS/config"
# The sandbox `nvim` is a symlink into the repository. Remove the link
# itself and never follow it. `rm -rf` on a symlink to a directory is
# safe on GNU coreutils, but relying on that is a subtle trap, so the
# link is unlinked explicitly instead.
if [ -L "$SANDBOX_CONFIG/nvim" ]; then
  unlink "$SANDBOX_CONFIG/nvim"
elif [ -d "$SANDBOX_CONFIG/nvim" ]; then
  # A real directory here means the link was replaced by a directory.
  # Remove only its contents, so nothing outside the sandbox is touched.
  find "$SANDBOX_CONFIG/nvim" -mindepth 1 -depth -delete 2>/dev/null
  rmdir "$SANDBOX_CONFIG/nvim" 2>/dev/null
fi
mkdir -p "$SANDBOX_CONFIG"
ln -sfn "$REPO" "$SANDBOX_CONFIG/nvim"

# Fail loudly if the sandbox is not the repo. A mismatch means the harness
# would validate a different configuration than the one under test.
if [ ! -e "$SANDBOX_CONFIG/nvim/lua/config/lazy.lua" ]; then
  echo "FATAL: sandbox config does not resolve to the repo at $REPO" >&2
  exit 1
fi
if [ "$(cd "$SANDBOX_CONFIG/nvim" && pwd -P)" != "$(cd "$REPO" && pwd -P)" ]; then
  echo "FATAL: sandbox config points at $(readlink -f "$SANDBOX_CONFIG/nvim"), not $REPO" >&2
  exit 1
fi

export XDG_DATA_HOME="$DATA"
export XDG_STATE_HOME="$DEPS/state"
export XDG_CACHE_HOME="$DEPS/cache"
export XDG_CONFIG_HOME="$SANDBOX_CONFIG"
export RF_REPO="$REPO"
export PATH="$DATA/nvim/mason/bin:$PATH"

mkdir -p "$DEPS/state" "$DEPS/cache" "$DEPS/work"

# Run from the repository root.
#
# Two paths depend on the working directory:
#   * the suites are given as repo-relative paths, and mini.test resolves
#     them relative to the parent's cwd.
#   * the child is started with `-u harness_init.lua`, a relative path, so
#     the child inherits this cwd and finds the init file.
cd "$REPO" || exit 1

# The suites to run. Each one is a separate mini.test file.
SUITES=${*:-"tests/suites/refactoring.lua tests/suites/smoke.lua"}

status=0
for suite in $SUITES; do
  echo "======== $suite ========"
  timeout 900 nvim --headless -u NONE \
    -c "lua vim.opt.rtp:prepend('$MINI_DIR')" \
    -c "lua require('mini.test').setup()" \
    -c "lua MiniTest.run_file('$suite')" \
    2>&1
  rc=$?
  echo "############ $suite EXIT: $rc ############"
  [ "$rc" -eq 0 ] || status=1
done

exit "$status"
