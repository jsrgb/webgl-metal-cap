#!/bin/zsh
set -eu

lab_dir="$(cd "$(dirname "$0")" && pwd)"
webkit_dir="$lab_dir/WebKit"
browser="$webkit_dir/WebKitBuild/Release/MiniBrowser.app/Contents/MacOS/MiniBrowser"
source "$lab_dir/webkit.lock"
failures=0

check() {
  local label="$1"
  shift
  if "$@"; then
    print "✓ $label"
  else
    print "✗ $label"
    failures=$((failures + 1))
  fi
}

at_pinned_revision() {
  [[ -d "$webkit_dir/.git" ]] && [[ "$(git -C "$webkit_dir" rev-parse HEAD 2>/dev/null)" = "$WEBKIT_REVISION" ]]
}

xcode_major() {
  xcodebuild -version 2>/dev/null | awk '/^Xcode / { print $2 }' | cut -d. -f1
}

print "Metal Web Capture Lab doctor"
check "Apple Silicon" test "$(uname -m)" = arm64
check "Full Xcode selected" xcodebuild -version
check "Tested Xcode major ($TESTED_XCODE_MAJOR)" test "$(xcode_major)" = "$TESTED_XCODE_MAJOR"
check "Git available" command -v git
check "Python 3 available" command -v python3
check "curl available" command -v curl
check "notifyutil available" command -v notifyutil
check "Pinned WebKit checkout present" test -d "$webkit_dir/.git"
check "WebKit revision matches webkit.lock" at_pinned_revision
check "Release MiniBrowser built" test -x "$browser"
check "MiniBrowser WebGPU preference patch present" grep -q 'WebGPUEnabled' "$webkit_dir/Tools/MiniBrowser/mac/AppDelegate.m"

if (( failures )); then
  print "\nFix the failed checks, then run ./doctor.command again."
  exit 1
fi

print "\nReady. Run ./run.command, then use window.metalCapture.start() and stop() from your app or DevTools."
