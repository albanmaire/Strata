#!/bin/sh
# strata-bootstrap.sh - Strata's Linux bootstrap: uv does everything.
# Finds uv (PATH, or the .uvbin folder) and installs it with its official installer when it is nowhere
# (pinned, into .uvbin, no sudo, no PATH edit).  'uv venv' then makes .venv: uv uses a Python 3.10+ already
# on the PC and downloads its own CPython only when none is found - apt/dnf/pacman and sudo are gone from
# this script (setup.py still uses sudo for build tools when it compiles the engine).
# STRATA.sh is the thin entry; this file holds the whole logic.
# The git pull of --update is NOT here: it lives in setup.py (fetch_new_code), so no script has to run
# git pull inside itself.
# Needs only an NVIDIA driver (or, for an AMD Radeon card, the kernel's amdgpu driver: see docs/AMD_HIP.md).
cd "$(dirname "$0")/.." || exit 1
UV_VERSION=0.12.23   # the same pin setup.py uses

find_uv() {
  command -v uv 2>/dev/null && return 0
  for c in .uvbin/uv .uvbin/bin/uv .uvbin/uv.exe .uvbin/bin/uv.exe; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

install_uv() {
  # progress and the installer's own output go to stderr: the function's stdout is ONLY the uv path
  echo "  Installing uv $UV_VERSION (Python and packages manager) into .uvbin ..." >&2
  if command -v curl >/dev/null 2>&1; then FETCH="curl -LsSf"; else FETCH="wget -qO-"; fi
  { $FETCH "https://astral.sh/uv/$UV_VERSION/install.sh" | UV_INSTALL_DIR="$PWD/.uvbin" UV_NO_MODIFY_PATH=1 sh; } 1>&2
  find_uv
}

if [ ! -x .venv/bin/python ]; then
  UV="$(find_uv || true)"
  [ -n "$UV" ] || UV="$(install_uv || true)"
  if [ -z "$UV" ]; then
    echo "uv could not be installed automatically (no internet, or curl/wget missing)."
    echo "Install uv $UV_VERSION (https://docs.astral.sh/uv/) and run ./STRATA.sh again."
    echo "On NixOS, add uv to environment.systemPackages."
    exit 1
  fi
  # uv makes the environment: a Python 3.10+ already on the PC is used as it is; only when none is found does
  # uv download its own CPython (a folder of its own, no sudo).  On NixOS uv's own Python is forced: Nix's
  # Python cannot load the wheels' libraries through dlopen.
  MANAGED=""
  grep -qi '^ID=nixos' /etc/os-release 2>/dev/null && MANAGED="--managed-python"
  "$UV" venv $MANAGED --python '>=3.10' .venv \
    || { echo "Could not create the Python environment in .venv (a half-made .venv: delete the folder and try again)."; exit 1; }
  # 64-bit, like the old probe guaranteed (a 32-bit Python cannot hold the model)
  .venv/bin/python -c 'import sys; sys.exit(0 if sys.maxsize > 2**32 else 1)' \
    || { echo "Strata needs 64-bit Python; the environment in .venv is 32-bit."; exit 1; }
fi
exec .venv/bin/python setup.py "$@"
