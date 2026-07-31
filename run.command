#!/bin/zsh
set -eu

lab_dir="$(cd "$(dirname "$0")" && pwd)"
webkit_dir="$lab_dir/WebKit"
browser="$webkit_dir/WebKitBuild/Release/MiniBrowser.app/Contents/MacOS/MiniBrowser"
product_dir="$webkit_dir/WebKitBuild/Release"

if [[ ! -x "$browser" ]]; then
  print "MiniBrowser is missing. Run ./bootstrap-webkit.command first."
  exit 1
fi

server_pid=""
browser_pid=""
port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
state_file="$lab_dir/.metal-web-capture-port"
cleanup() {
  if [[ -n "$browser_pid" ]] && kill -0 "$browser_pid" 2>/dev/null; then
    kill "$browser_pid" 2>/dev/null || true
    wait "$browser_pid" 2>/dev/null || true
  fi
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -f "$state_file"
}
trap cleanup EXIT INT TERM

cd "$lab_dir"
python3 capture_server.py --port "$port" &
server_pid=$!
print -r -- "$port" > "$state_file"

for _ in {1..20}; do
  if curl --silent --fail "http://127.0.0.1:$port/" >/dev/null 2>&1; then
    break
  fi
  sleep .1
done
if ! kill -0 "$server_pid" 2>/dev/null; then
  print "Could not start the local capture server."
  exit 1
fi

defaults write org.webkit.MiniBrowser WebGPUEnabled -bool true
env \
  __XPC_METAL_CAPTURE_ENABLED=1 \
  DYLD_FRAMEWORK_PATH="$product_dir" \
  __XPC_DYLD_FRAMEWORK_PATH="$product_dir" \
  DYLD_LIBRARY_PATH="$product_dir" \
  __XPC_DYLD_LIBRARY_PATH="$product_dir" \
  WEBKIT_UNSET_DYLD_FRAMEWORK_PATH=YES \
  "$browser" --url "http://127.0.0.1:$port/" --mac &
browser_pid=$!
wait "$browser_pid"
