@echo off
REM Spacestation SP launcher.
REM
REM Two things this gets right that double-clicking tgstation.dmb does not:
REM
REM   -trusted    /tg/station requires the Trusted security level. At Safe, BYOND asks permission for
REM               every single file the game reads, which means hundreds of "Safety check" dialogs on
REM               startup (the AI crew each load several behaviour-tree files), and the native
REM               libraries rust_g and dreamluau cannot load at all.
REM
REM   port 7777   Razer Synapse's RzSDKServer listens on 127.0.0.1:1337. A loopback-bound socket beats
REM               Dream Daemon's wildcard bind, so a client connecting to 1337 reaches Razer instead of
REM               BYOND and fails the handshake while the game server logs nothing.
REM
REM Connect with Dream Seeker to:  byond://127.0.0.1:7777

setlocal
set "PORT=7777"
if not "%~1"=="" set "PORT=%~1"

if not exist "%~dp0tgstation.dmb" (
	echo tgstation.dmb not found. Run BUILD.cmd first.
	pause
	exit /b 1
)

for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Dantom\BYOND" /v installpath 2^>nul ^| find "installpath"') do set "BYOND=%%B"
if not defined BYOND for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\Dantom\BYOND" /v installpath 2^>nul ^| find "installpath"') do set "BYOND=%%B"
if not defined BYOND set "BYOND=C:\Program Files (x86)\BYOND"

if not exist "%BYOND%\bin\dreamdaemon.exe" (
	echo Could not find dreamdaemon.exe under "%BYOND%".
	pause
	exit /b 1
)

echo Starting Spacestation SP on port %PORT% at Trusted security.
echo Connect to byond://127.0.0.1:%PORT%
"%BYOND%\bin\dreamdaemon.exe" "%~dp0tgstation.dmb" %PORT% -trusted
endlocal
