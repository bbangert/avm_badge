#!/usr/bin/env bash
# Pack firmware/assets.avm and write it to the assets partition.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
avm="$root/firmware/assets.avm"

offset=0x278000
size=262144
chip=esp32s3

port="${1:-${PORT:-}}"
if [ -z "$port" ]; then
  ports=( /dev/cu.usbmodem* )
  if [ ! -e "${ports[0]}" ]; then
    echo "flashassets: no /dev/cu.usbmodem* found, is the badge plugged in?" >&2
    exit 1
  fi
  if [ "${#ports[@]}" -gt 1 ]; then
    echo "flashassets: several ports, pass one: ${ports[*]}" >&2
    exit 1
  fi
  port="${ports[0]}"
fi

"$(dirname "$0")/mkassets.sh" >/dev/null

actual="$(wc -c <"$avm" | tr -d ' ')"
if [ "$actual" -gt "$size" ]; then
  echo "flashassets: assets.avm is ${actual}B, partition holds ${size}B" >&2
  exit 1
fi
echo "flashassets: ${actual}B of ${size}B, writing to $port"

esptool.py --chip "$chip" --port "$port" --baud 921600 write_flash "$offset" "$avm"

echo "flashassets: done, the badge has reset"
