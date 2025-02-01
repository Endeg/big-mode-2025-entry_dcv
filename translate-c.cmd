@echo off
zig translate-c --library c -Ilibs\raylib libs\all.h > src\c.zig
