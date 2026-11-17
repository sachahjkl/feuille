#!/usr/bin/env bash
# Shortcut: ./build.sh [release] is feuilletool build.
# Every other step: odin run tools/feuilletool -collection:gt=ext/gui_toolkit/src -out:build/feuilletool -- <command> (help lists them).
cd "$(dirname "$0")" && mkdir -p build && exec odin run tools/feuilletool -collection:gt=ext/gui_toolkit/src -out:build/feuilletool -keep-executable -- build "$@"
