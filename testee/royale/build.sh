#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_dir/testee/bin/royale"
if [[ -z "${ROYALE_SDK:-}" || ! -x "$ROYALE_SDK/js/bin/asnodec" ]]; then
    echo 'Set ROYALE_SDK to the royale-asjs directory of Apache Royale 0.9.12.' >&2
    exit 1
fi

mkdir -p "$build_dir/src"
cp "$repo_dir/testee/royale/Main.as" "$build_dir/src/Main.as"
# Copy only the shared handler: the AIR entry point has the same class name.
cp "$repo_dir/testee/src/ConformanceCodec.as" "$build_dir/src/ConformanceCodec.as"
"$ROYALE_SDK/js/bin/asnodec" \
    -debug=false \
    -define+=COMPILE::JS,true \
    -js-vector-emulation-class=Array \
    -js-vector-index-checks=false \
    -library-path+="$ROYALE_SDK/frameworks/js/libs/CoreJS.swc" \
    -library-path+="$ROYALE_SDK/frameworks/js/libs/XMLJS.swc" \
    -source-path+="$repo_dir/as3pb/runtime/royale/src" \
    -source-path+="$repo_dir/as3pb/runtime/src" \
    -source-path+="$repo_dir/testee/generated" \
    "$build_dir/src/Main.as"

test -f "$build_dir/bin/js-release/index.js"
