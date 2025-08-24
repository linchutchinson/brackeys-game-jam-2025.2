@echo off
setlocal enabledelayedexpansion
cd /D "%~dp0"

if not exist out mkdir out

for %%a in (%*) do set "%%a=1"

set odin=odin-windows\odin.exe

set flags=-debug -out:out/bgj.exe -strict-style -vet

%odin% build src %flags%
