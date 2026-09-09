@echo off
cls
zig build run -freference-trace=16 --summary line --error-style minimal_clear
