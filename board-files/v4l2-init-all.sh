#!/bin/bash
# Init every CRU (RZG2L) camera pipe to one coherent size.
# Video/media indices are unstable across boots (UVC may probe first), so
# discover media devices by topology ('CRU output' entity) instead of index.
# CRU registers async after boot — retry until it appears (max ~30s).
W=${1:-1920}; H=${2:-1080}
for try in $(seq 1 30); do
  ok=0
  for m in /dev/media*; do
    [ -e "$m" ] || continue
    node=$(media-ctl -d "$m" -e 'CRU output' 2>/dev/null | awk '{print $1}')
    [ -n "$node" ] || continue
    idx=${m#/dev/media}
    /usr/local/bin/v4l2-init.sh --device "$idx" --width "$W" --height "$H" && ok=1
  done
  [ "$ok" -gt 0 ] && exit 0
  sleep 1
done
echo "v4l2-init-all: no CRU media device found" >&2
exit 1
