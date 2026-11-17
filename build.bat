@echo off
rem Shortcut: build.bat [release] is feuilletool build.
rem Every other step: odin run tools/feuilletool -collection:gt=ext/gui_toolkit/src -out:build/feuilletool -- <command> (help lists them).
cd /d "%~dp0"
if not exist build mkdir build
odin run tools/feuilletool -collection:gt=ext/gui_toolkit/src -out:build/feuilletool -keep-executable -- build %*
