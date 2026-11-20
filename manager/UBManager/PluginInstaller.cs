using System;
using System.IO;
using System.IO.Compression;
using System.Linq;

namespace UBManager
{
    /// <summary>Installs, updates, rolls back and uninstalls a plugin folder atomically.</summary>
    internal static class PluginInstaller
    {
        public const string PluginId = "utilitybelt";

        public static bool IsLink(string dir) =>
            Directory.Exists(dir) && (File.GetAttributes(dir) & FileAttributes.ReparsePoint) != 0;

        public static string InstalledVersion(ClientTarget t)
        {
            var manifest = Path.Combine(t.PluginDir(PluginId), "plugin.json");
            if (!File.Exists(manifest)) return null;
            try { return Json.Get(Json.ReadObjectFile(manifest), "version") ?? "?"; }
            catch { return "?"; }
        }

        private static string BackupDir(ClientTarget t) => Path.Combine(t.ManagerWorkDir, "backup", PluginId);

        public static string BackupVersion(ClientTarget t)
        {
            var manifest = Path.Combine(BackupDir(t), "plugin.json");
            if (!File.Exists(manifest)) return null;
            try { return Json.Get(Json.ReadObjectFile(manifest), "version"); } catch { return null; }
        }

        /// <summary>
        /// Extracts a verified zip into staging, checks its manifest, then swaps it in.
        /// The current version becomes the single backup. Any failure restores the original.
        /// </summary>
        public static void InstallFromZip(ClientTarget t, string zipPath, Action<string> log)
        {
            var live = t.PluginDir(PluginId);
            if (IsLink(live))
                throw new InvalidOperationException("The installed plugin folder is a link (developer setup). Update it with git instead.");

            var staging = Path.Combine(t.ManagerWorkDir, "staging");
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
            Directory.CreateDirectory(staging);

            using (var zip = ZipFile.OpenRead(zipPath))
            {
                foreach (var entry in zip.Entries)
                {
                    var name = entry.FullName.Replace('\\', '/');
                    if (name.Contains("../") || Path.IsPathRooted(name)) throw new InvalidDataException("Unsafe path in zip: " + name);
                    if (!name.StartsWith(PluginId + "/", StringComparison.Ordinal)) throw new InvalidDataException("Unexpected zip layout: " + name);
                    var dest = Path.GetFullPath(Path.Combine(staging, name));
                    if (!dest.StartsWith(Path.GetFullPath(staging), StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Unsafe path in zip: " + name);
                    if (name.EndsWith("/")) { Directory.CreateDirectory(dest); continue; }
                    Directory.CreateDirectory(Path.GetDirectoryName(dest));
                    entry.ExtractToFile(dest, true);
                }
            }

            var stagedPlugin = Path.Combine(staging, PluginId);
            var manifest = Path.Combine(stagedPlugin, "plugin.json");
            if (!File.Exists(manifest) || !File.Exists(Path.Combine(stagedPlugin, "main.lua")))
                throw new InvalidDataException("The download does not contain a complete plugin.");
            if (Json.Get(Json.ReadObjectFile(manifest), "id") != PluginId)
                throw new InvalidDataException("The download is not the UtilityBelt plugin.");

            Directory.CreateDirectory(t.InstalledDir);
            var backup = BackupDir(t);
            var oldBackup = backup + ".old";
            if (Directory.Exists(oldBackup)) Directory.Delete(oldBackup, true);
            var hadLive = Directory.Exists(live);
            var hadBackup = Directory.Exists(backup);
            try
            {
                if (hadLive)
                {
                    if (hadBackup) Directory.Move(backup, oldBackup);
                    Directory.CreateDirectory(Path.GetDirectoryName(backup));
                    Directory.Move(live, backup);
                }
                Directory.Move(stagedPlugin, live);
                if (Directory.Exists(oldBackup)) Directory.Delete(oldBackup, true);
                log?.Invoke("Installed version " + InstalledVersion(t) + (hadLive ? "; the previous version is kept for rollback." : "."));
            }
            catch
            {
                // Put everything back the way it was.
                if (!Directory.Exists(live) && Directory.Exists(backup) && hadLive) Directory.Move(backup, live);
                if (!Directory.Exists(backup) && Directory.Exists(oldBackup)) Directory.Move(oldBackup, backup);
                throw;
            }
            finally
            {
                try { if (Directory.Exists(staging)) Directory.Delete(staging, true); } catch { }
            }
        }

        public static void Rollback(ClientTarget t, Action<string> log)
        {
            var live = t.PluginDir(PluginId);
            var backup = BackupDir(t);
            if (IsLink(live)) throw new InvalidOperationException("The installed plugin folder is a link (developer setup).");
            if (!Directory.Exists(backup)) throw new InvalidOperationException("There is no previous version to restore.");
            var swap = backup + ".swap";
            if (Directory.Exists(swap)) Directory.Delete(swap, true);
            if (Directory.Exists(live)) Directory.Move(live, swap);
            Directory.Move(backup, live);
            if (Directory.Exists(swap)) Directory.Move(swap, backup);   // the rolled-back version becomes the new backup
            log?.Invoke("Restored version " + InstalledVersion(t) + ".");
        }

        public static void Uninstall(ClientTarget t, bool removeSavedData, Action<string> log)
        {
            var live = t.PluginDir(PluginId);
            if (IsLink(live)) throw new InvalidOperationException("The installed plugin folder is a link (developer setup); remove it yourself.");
            if (Directory.Exists(live)) Directory.Delete(live, true);
            var work = t.ManagerWorkDir;
            if (Directory.Exists(work)) Directory.Delete(work, true);
            if (removeSavedData)
            {
                foreach (var dir in new[] { Path.Combine(t.ClientPluginsDir, "Profiles", PluginId), Path.Combine(t.ClientPluginsDir, "State", PluginId) })
                    if (Directory.Exists(dir)) Directory.Delete(dir, true);
            }
            log?.Invoke(removeSavedData ? "Removed UtilityBelt and its saved settings." : "Removed UtilityBelt. Its saved settings were kept.");
        }

        /// <summary>Semantic-version comparison (pre-releases sort before their release).</summary>
        public static int CompareVersions(string a, string b)
        {
            if (a == b) return 0;
            if (string.IsNullOrEmpty(a) || a == "?") return -1;
            if (string.IsNullOrEmpty(b) || b == "?") return 1;
            Split(a, out var na, out var pa);
            Split(b, out var nb, out var pb);
            for (var i = 0; i < 3; i++) if (na[i] != nb[i]) return na[i].CompareTo(nb[i]);
            if (pa == null) return pb == null ? 0 : 1;
            if (pb == null) return -1;
            var xa = pa.Split('.'); var xb = pb.Split('.');
            for (var i = 0; i < Math.Min(xa.Length, xb.Length); i++)
            {
                var ia = int.TryParse(xa[i], out var va); var ib = int.TryParse(xb[i], out var vb);
                var c = ia && ib ? va.CompareTo(vb) : ia ? -1 : ib ? 1 : string.CompareOrdinal(xa[i], xb[i]);
                if (c != 0) return c;
            }
            return xa.Length.CompareTo(xb.Length);
        }

        private static void Split(string v, out int[] nums, out string pre)
        {
            var dash = v.IndexOf('-');
            pre = dash >= 0 ? v.Substring(dash + 1) : null;
            var core = (dash >= 0 ? v.Substring(0, dash) : v).Split('.');
            nums = Enumerable.Range(0, 3).Select(i => i < core.Length && int.TryParse(core[i], out var n) ? n : 0).ToArray();
        }
    }
}
