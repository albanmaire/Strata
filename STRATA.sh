#!/bin/sh
# Strata (Linux): the first run installs everything and starts the model; later runs just start it.
# Options: --setup (install another model / change settings), --update (fetch the newest code and refresh
# the install without starting), --no-start, --calibrate, --model/--context/--gpus ... (setup.py passes them on).
# All the logic lives in scripts/strata-bootstrap.sh; this file only launches it.
exec sh "$(dirname "$0")/scripts/strata-bootstrap.sh" "$@"
