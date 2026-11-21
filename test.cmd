@echo off
zig build test -freference-trace=16 --summary line --error-style minimal_clear %*
