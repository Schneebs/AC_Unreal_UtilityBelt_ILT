# AC_Unreal_UtilityBelt - Currently a work in progress as I get started with unreal

A port of UtilityBelt features to the [AC:Unreal](https://github.com/Thwargle/ACE) client plugin API (Lua).

This is a plugin, not part of the client. Plugins live in their own repos and are
installed into the client's plugin folder, like Decal plugins. Client changes and
plugin-API additions go to [Thwargle/ACE](https://github.com/Thwargle/ACE).

## Status

Scaffold only: the plugin loads and shows your health in the Plugin Manager.

## Install

Copy (or link) the `utilitybelt` folder into the client's user plugin folder:

```
<AC:Unreal>/Saved/ClientPlugins/Installed/utilitybelt/
```

Then open the Plugin Manager in game (`/acueplugins`) and press **Reload installed plugins**.

For development on Windows, link it instead of copying, so edits show up after a reload:

```powershell
New-Item -ItemType Junction -Path '<AC:Unreal>\Unreal\Saved\ClientPlugins\Installed\utilitybelt' -Target '<this repo>\utilitybelt'
```

## Layout

| File | Purpose |
| --- | --- |
| `utilitybelt/plugin.json` | Manifest: ID, mode, permissions, settings |
| `utilitybelt/main.lua` | Returns `function(snapshot, profile)` |
| `utilitybelt/default.json` | Default profile |

## API gaps

UtilityBelt features the AC:Unreal plugin API can't support yet. These become requests to Thwargle.

| UB feature | What the API is missing | Raised |
| --- | --- | --- |
| | | |
