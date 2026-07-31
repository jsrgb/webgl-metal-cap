#!/bin/zsh
set -eu

lab_dir="$(cd "$(dirname "$0")" && pwd)"
state_file="$lab_dir/.metal-web-capture-port"
submit_count="${1:-3}"

if [[ ! -r "$state_file" ]]; then
  print "The lab is not running. Start ./run.command first."
  exit 1
fi
port="$(<"$state_file")"
if [[ "$submit_count" != <-> ]] || (( submit_count < 1 || submit_count > 2000 )); then
  print "Choose a whole number of WebGPU submits from 1 to 2000."
  exit 1
fi
result="$(curl --fail --silent --show-error -X POST -H 'Content-Type: application/json' --data "{\"commands\":$submit_count}" "http://127.0.0.1:$port/api/capture")"
path="$(print -r -- "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin)["path"])')"
print "Saved GPU trace: $path"
