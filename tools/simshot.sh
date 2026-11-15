#!/bin/bash
# Headless simulator run inside the "garmin" distrobox; saves a screenshot.
# usage: tools/simshot.sh <out.png> [seconds-to-wait]
SDK=$(cat ~/.Garmin/ConnectIQ/current-sdk.cfg)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/bin/sim.png}
export DISPLAY=:97 GDK_BACKEND=x11
unset WAYLAND_DISPLAY LD_LIBRARY_PATH
Xvfb :97 -screen 0 1400x1000x24 >/dev/null 2>&1 &
XV=$!
sleep 1
"$SDK/bin/simulator" >/tmp/ciq-sim.log 2>&1 &
SIM=$!
sleep 8
timeout 40 "$SDK/bin/monkeydo" "$ROOT/bin/glitchterm.prg" venu445mm >/tmp/ciq-run.log 2>&1 &
sleep ${2:-12}
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do import -window root "${OUT%.png}-$i.png"; done
kill $SIM $XV 2>/dev/null

echo "--- run log"; tail -15 /tmp/ciq-run.log; echo "--- sim log"; tail -5 /tmp/ciq-sim.log
