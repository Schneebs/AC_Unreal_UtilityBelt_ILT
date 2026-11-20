using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Win32;

namespace UBManager
{
    /// <summary>An AC:Unreal client whose ClientPlugins folder UB Manager manages.</summary>
    internal sealed class ClientTarget
    {
        public string Label;
        public string ClientPluginsDir;   // ...\Saved\ClientPlugins
        public bool Detected;             // found automatically (vs. added by the player)

        public string InstalledDir => Path.Combine(ClientPluginsDir, "Installed");
        public string PluginDir(string id) => Path.Combine(InstalledDir, id);
        public string LibraryDir(string id) => Path.Combine(ClientPluginsDir, "Profiles", id, "Library");
        // Staging and backups live outside Installed: the client scans every folder
        // in Installed, and a second copy there would be a duplicate plugin ID.
        public string ManagerWorkDir => Path.Combine(ClientPluginsDir, "UBManager");

        public override string ToString() => Label + "  —  " + ClientPluginsDir;
    }

    internal static class ClientLocator
    {
        // Inno Setup AppId of the AC:Unreal installer (Unreal/Build/VR/Windows-Installer.iss).
        private const string InstallerKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\{1A8CDD07-D4C5-4F9E-9788-08636A6D7C31}_is1";

        public static List<ClientTarget> Find(IEnumerable<string> extraFolders)
        {
            var found = new List<ClientTarget>();
            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

            // Installed client: Saved lives under %LOCALAPPDATA%\ACUnreal\Saved.
            var installedLocation = ReadInstallLocation() ?? Path.Combine(local, "Programs", "ACUnreal");
            var packagedSaved = Path.Combine(local, "ACUnreal", "Saved", "ClientPlugins");
            if (Directory.Exists(installedLocation) || Directory.Exists(packagedSaved))
                found.Add(new ClientTarget { Label = "AC:Unreal (installed)", ClientPluginsDir = packagedSaved, Detected = true });

            foreach (var folder in extraFolders ?? Enumerable.Empty<string>())
            {
                var target = FromFolder(folder);
                if (target != null && !found.Any(f => SamePath(f.ClientPluginsDir, target.ClientPluginsDir)))
                    found.Add(target);
            }
            return found;
        }

        /// <summary>Accepts a source checkout, its Unreal folder, a Saved folder or a ClientPlugins folder.</summary>
        public static ClientTarget FromFolder(string folder)
        {
            if (string.IsNullOrWhiteSpace(folder) || !Directory.Exists(folder)) return null;
            var full = Path.GetFullPath(folder).TrimEnd('\\', '/');
            if (Path.GetFileName(full).Equals("ClientPlugins", StringComparison.OrdinalIgnoreCase))
                return new ClientTarget { Label = "Custom", ClientPluginsDir = full };
            if (File.Exists(Path.Combine(full, "Unreal", "ACUnreal.uproject")))
                return new ClientTarget { Label = "Source build", ClientPluginsDir = Path.Combine(full, "Unreal", "Saved", "ClientPlugins") };
            if (File.Exists(Path.Combine(full, "ACUnreal.uproject")))
                return new ClientTarget { Label = "Source build", ClientPluginsDir = Path.Combine(full, "Saved", "ClientPlugins") };
            if (Directory.Exists(Path.Combine(full, "ClientPlugins")))
                return new ClientTarget { Label = "Custom", ClientPluginsDir = Path.Combine(full, "ClientPlugins") };
            return null;
        }

        private static string ReadInstallLocation()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(InstallerKey))
                    return key?.GetValue("InstallLocation") as string;
            }
            catch { return null; }
        }

        public static bool SamePath(string a, string b) =>
            string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
    }
}
