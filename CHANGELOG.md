# Changelog

## Unreleased

- Added `installmods.bat` installer support for Steam Icarus installations.
- Installer now finds the Icarus install path automatically.
- Installer wipes the game's `Icarus\Content\Paks\mods` folder before installing this modpack.
- Installer removes UE4SS artifacts from `Icarus\Binaries\Win64`, including the `ue4ss` folder and `dwmapi.dll`.
- Updated the release pipeline to include `installmods.bat` in release archives.
