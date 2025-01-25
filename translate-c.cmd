@echo off
zig translate-c --library c -Ilibs\raylib\include libs\all.h > src\c.zig
