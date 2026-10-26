#!/bin/sh
#
# Quits the running Barbarian, if any, and opens the installed copy.
#
# Usage: scripts/restart-app.sh

set -eu

for pid in $(pgrep -x Barbarian || true); do
    kill "$pid"
done
while pgrep -x Barbarian > /dev/null; do sleep 0.2; done
open "$HOME/Applications/Barbarian.app"
