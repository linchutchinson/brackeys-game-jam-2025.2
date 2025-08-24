@echo off
setlocal enabledelayedexpansion
cd /D "%~dp0"

if not exist out mkdir out

for %%a in (%*) do set "%%a=1"

set odin=odin-windows\odin.exe

set flags=-debug -strict-style -vet -define:RAYLIB_SHARED=true

if "%core%"=="1" (
	echo [Core]
	%odin% build src %flags% -out:out/bgj.exe
)

if "%hot%" == "1" (
	echo [Hot]
	%odin% build src %flags% -out:out/bgj_tmp.dll -build-mode:dll && move out\bgj_tmp.dll out\bgj.dll
	if not exist out\raylib.dll copy odin-windows\vendor\raylib\windows\raylib.dll out\raylib.dll
)
