@echo off
cls
@REM Add `--watch` when compiler assisted refactoring is needed
zig build -freference-trace=16 --summary line --error-style minimal_clear %*
