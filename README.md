# AC_Unreal_UtilityBelt - Currently a work in progress as I get started with unreal

A port of UtilityBelt features to the [AC:Unreal](https://github.com/Thwargle/ACE) client plugin API (Lua).

This is a plugin, not part of the client. Plugins live in their own repos and are
installed into the client's plugin folder, like Decal plugins. Client changes and
plugin-API additions go to [Thwargle/ACE](https://github.com/Thwargle/ACE).

## Status

Early development. The plugin loads, shows its version and your health, and can apply your
retail UtilityBelt settings (Import from retail). No UB tools are ported yet.

## Install with UB Manager (recommended)

Download `UBManager.exe` from the [releases](https://github.com/Schneebs/AC_Unreal_UtilityBelt_ILT/releases) and run it.
It needs no installer or administrator rights (Windows 10/11, .NET Framework 4.8, which Windows includes).

- **Install / Update:** finds your AC:Unreal client, downloads the plugin, checks its SHA-256 and installs it.
  The previous version is kept for **Roll back**. Choose the **Stable** or **Beta** channel.
- **Retail import:** reads your retail UtilityBelt folder (`Documents\Decal Plugins\UtilityBelt`) without changing it,
  and copies settings, per-character files, named profiles, global variables and quest flags into the plugin's
  profile library. Tick the worlds you want. Then, in game, press **Import from retail** in UtilityBelt
  (it also runs automatically the first time each character logs in).
- **Import ThwargLauncher logins:** copies ThwargLauncher's servers and accounts (`%APPDATA%\ThwargLauncher`)
  into AC:Unreal's login screen, optionally with saved passwords (stored DPAPI-encrypted for your Windows user,
  as AC:Unreal does). Existing AC:Unreal entries are kept, duplicates skipped, and the old login file is backed up.
  Close AC:Unreal first.
- **Update UB Manager** appears when a newer version is released. **Install UB Manager for this user**
  copies it to `%LOCALAPPDATA%\UBManager` with a Start menu shortcut.
- Windows SmartScreen may warn because the exe isn't signed yet; compare it with the `.sha256` on the release page.

UB Manager also has a command line for scripting and testing:
`UBManager.exe --check [stable|beta]`, `--scan <retail folder>`, `--import <retail folder> <ClientPlugins folder> [--worlds=A,B]`,
`--install <ClientPlugins folder> [stable|beta]`, `--rollback <folder>`, `--uninstall <folder> [--all]`,
`--thwarg-import <ThwargLauncher folder|default> <client folder> [--no-passwords] [--dry-run]`, plus `--log=<file>`.

## Install by hand

Download `utilitybelt-<version>.zip` from the [latest release](https://github.com/Schneebs/AC_Unreal_UtilityBelt_ILT/releases/latest)
and extract it into the client's user plugin folder, so you end up with:

```
%LOCALAPPDATA%\Programs\ACUnreal\ACUnreal\Saved\ClientPlugins\Installed\utilitybelt\
```

(For a source build of the client: `<repo>\Unreal\Saved\ClientPlugins\Installed\utilitybelt\`.)

Then open the Plugin Manager in game (`/acueplugins`) and press **Refresh**.
Each release lists a `.sha256` checksum for the zip if you want to verify the download.

## Development

Source lives in `plugin/src` as separate Lua modules. The client sandbox has no `require`,
so the build concatenates them (in file-name order) into one `main.lua`.

Build (Windows PowerShell 5.1 or PowerShell 7):

```powershell
./tools/build-plugin.ps1
```

This lints `plugin/src` for functions the sandbox doesn't provide, then writes `dist/utilitybelt`.
Link the client's plugin folder to the build output once, then rebuild and press **Refresh** after each change:

```powershell
New-Item -ItemType Junction -Path '<client>\Saved\ClientPlugins\Installed\utilitybelt' -Target '<this repo>\dist\utilitybelt'
```

Tests (Lua 5.4) run in CI on every push; locally:

```powershell
lua5.4 tools/test/run_tests.lua dist/utilitybelt/main.lua tools/test/cases/startup.lua
```

## Releasing

Push a tag: `v0.1.0` publishes a stable release, `v0.2.0-beta.1` a pre-release (Beta channel).
GitHub Actions lints, builds, syntax-checks and tests the plugin, builds and smoke-tests UB Manager,
then attaches `utilitybelt-<version>.zip`, `UBManager.exe`, their `.sha256` files and `latest.json`
(read by UB Manager for updates) to the release.

## Layout

| Path | Purpose |
| --- | --- |
| `plugin/src/*.lua` | Lua modules, concatenated in name order into `main.lua` |
| `plugin/plugin.json` | Manifest: ID, mode, permissions, settings (version is stamped at build) |
| `plugin/default.json` | Default profile |
| `plugin/assets/` | `images/` and `sounds/` copied into the plugin |
| `tools/build-plugin.ps1` | Lint, build, package, checksum, `latest.json` |
| `tools/test/` | Snapshot test harness and cases |
| `manager/UBManager/` | UB Manager (C#, .NET Framework 4.8, WinForms; build with `dotnet build -c Release`) |
| `.github/workflows/release.yml` | CI and releases |

## API gaps

UtilityBelt features the AC:Unreal plugin API can't support yet. These become requests to Thwargle.

| UB feature | What the API is missing | Raised |
| --- | --- | --- |
| | | |
