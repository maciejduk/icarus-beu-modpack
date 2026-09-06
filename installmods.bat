@echo off
setlocal enabledelayedexpansion

set "FOUND=0"
set "INSTALL_PATH="
set "GAME_FOLDER=Icarus"

echo Searching for %GAME_FOLDER% install path...
echo.

REM --- Step 1: Get Steam install path from registry ---
set "STEAM_PATH="
for /f "tokens=2*" %%A in ('reg query "HKEY_CURRENT_USER\Software\Valve\Steam" /v SteamPath 2^>nul') do set "STEAM_PATH=%%B"

if "%STEAM_PATH%"=="" (
    for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" /v InstallPath 2^>nul') do set "STEAM_PATH=%%B"
)

if "%STEAM_PATH%"=="" (
    echo Could not find Steam install path in registry.
    goto :manual_check
)

echo Steam found at: %STEAM_PATH%

REM --- Step 2: Check default library first ---
if exist "!STEAM_PATH!\steamapps\common\%GAME_FOLDER%" (
    echo.
    echo FOUND: !STEAM_PATH!\steamapps\common\%GAME_FOLDER%
    set "FOUND=1"
    set "INSTALL_PATH=!STEAM_PATH!\steamapps\common\%GAME_FOLDER%"
    goto :end
)

REM --- Step 3: Parse libraryfolders.vdf for additional library drives ---
set "VDF=!STEAM_PATH!\steamapps\libraryfolders.vdf"
if not exist "!VDF!" goto :manual_check

for /f "tokens=2 delims=	" %%L in ('findstr /c:"\"path\"" "!VDF!"') do (
    set "LIBPATH=%%~L"
    set "LIBPATH=!LIBPATH:"=!"
    set "LIBPATH=!LIBPATH:\\=\!"
    if exist "!LIBPATH!\steamapps\common\%GAME_FOLDER%" (
        echo.
        echo FOUND: !LIBPATH!\steamapps\common\%GAME_FOLDER%
        set "FOUND=1"
        set "INSTALL_PATH=!LIBPATH!\steamapps\common\%GAME_FOLDER%"
    )
)

if "%FOUND%"=="1" goto :end

:manual_check
echo.
echo Not found via Steam metadata. Checking common drive letters...
for %%D in (C D E F G) do (
    if exist "%%D:\SteamLibrary\steamapps\common\%GAME_FOLDER%" (
        echo FOUND: %%D:\SteamLibrary\steamapps\common\%GAME_FOLDER%
        set "FOUND=1"
        set "INSTALL_PATH=%%D:\SteamLibrary\steamapps\common\%GAME_FOLDER%"
    )
    if exist "%%D:\Program Files (x86)\Steam\steamapps\common\%GAME_FOLDER%" (
        echo FOUND: %%D:\Program Files ^(x86^)\Steam\steamapps\common\%GAME_FOLDER%
        set "FOUND=1"
        set "INSTALL_PATH=%%D:\Program Files (x86)\Steam\steamapps\common\%GAME_FOLDER%"
    )
)

:end
echo.
if "%FOUND%"=="0" (
    echo Could not locate %GAME_FOLDER% automatically.
) else (
    set "SOURCE_MODS=%~dp0Content\Paks\mods"
    set "TARGET_MODS=!INSTALL_PATH!\Icarus\Content\Paks\mods"
    set "UE4SS_FOLDER=!INSTALL_PATH!\Icarus\Binaries\Win64\ue4ss"
    set "UE4SS_DLL=!INSTALL_PATH!\Icarus\Binaries\Win64\dwmapi.dll"

    if not exist "!SOURCE_MODS!" (
        echo Could not find source mods folder: !SOURCE_MODS!
        goto :pause
    )

    if exist "!TARGET_MODS!" rmdir /s /q "!TARGET_MODS!"
    if exist "!TARGET_MODS!" (
        echo Failed to wipe mods folder: !TARGET_MODS!
        goto :pause
    )
    mkdir "!TARGET_MODS!"
    if not exist "!TARGET_MODS!" (
        echo Failed to create mods folder: !TARGET_MODS!
        goto :pause
    )

    if exist "!UE4SS_FOLDER!" rmdir /s /q "!UE4SS_FOLDER!"
    if exist "!UE4SS_DLL!" del /f /q "!UE4SS_DLL!"
    if exist "!UE4SS_FOLDER!" (
        echo Failed to remove UE4SS folder: !UE4SS_FOLDER!
        goto :pause
    )
    if exist "!UE4SS_DLL!" (
        echo Failed to remove UE4SS DLL: !UE4SS_DLL!
        goto :pause
    )

    xcopy "!SOURCE_MODS!\*" "!TARGET_MODS!\" /E /I /Y >nul

    if errorlevel 1 (
        echo Failed to copy mods to: !TARGET_MODS!
    ) else (
        echo Mods installed
    )
)
:pause
pause