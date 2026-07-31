#!/bin/zsh
set -eu

lab_dir="$(cd "$(dirname "$0")" && pwd)"
webkit_dir="$lab_dir/WebKit"
source "$lab_dir/webkit.lock"

if [[ -e "$webkit_dir" ]]; then
  print "WebKit already exists at $webkit_dir"
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  print "Full Xcode is required. Install it, open it once, then select it with xcode-select."
  exit 1
fi

git clone --filter=blob:none --no-checkout "$WEBKIT_REMOTE" "$webkit_dir"
cd "$webkit_dir"
git fetch --depth 1 origin "$WEBKIT_REVISION"
git checkout --detach "$WEBKIT_REVISION"
git apply "$lab_dir/patches/minibrowser-webgpu.patch"
Tools/Scripts/build-webkit --release
