using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace UBManager
{
    /// <summary>
    /// Scriptable commands, used for testing the same code paths as the window:
    ///   --check [stable|beta]
    ///   --scan &lt;retail UB folder&gt;
    ///   --import &lt;retail UB folder&gt; &lt;ClientPlugins folder&gt;
    ///   --install &lt;ClientPlugins folder&gt; [stable|beta]
    ///   --rollback &lt;ClientPlugins folder&gt;
    ///   --uninstall &lt;ClientPlugins folder&gt; [--all]
    /// Add --log=&lt;file&gt; to also write output to a file. Exit code 0 means success.
    /// </summary>
    internal static class Cli
    {
        [DllImport("kernel32.dll")] private static extern bool AttachConsole(int processId);
        private static StreamWriter file;

        private static void Out(string line)
        {
            Console.WriteLine(line);
            file?.WriteLine(line);
        }

        public static int Run(string[] rawArgs)
        {
            AttachConsole(-1);
            var logArg = rawArgs.FirstOrDefault(a => a.StartsWith("--log=", StringComparison.Ordinal));
            if (logArg != null) file = new StreamWriter(logArg.Substring(6)) { AutoFlush = true };
            var args = rawArgs.Where(a => a != logArg).ToArray();
            try
            {
                switch (args[0])
                {
                    case "--check":
                    {
                        var latest = ReleaseFeed.GetLatestAsync(Arg(args, 1) ?? "stable").GetAwaiter().GetResult();
                        Out($"latest {latest.Version} ({latest.Channel}) plugin {latest.Plugin.Url} sha256 {latest.Plugin.Sha256}" +
                            (latest.Manager != null ? $" manager {latest.Manager.Version}" : " manager none"));
                        return 0;
                    }
                    case "--scan":
                    {
                        var scan = RetailImporter.Scan(Require(args, 1));
                        Out($"worlds {scan.Worlds.Count} characters {scan.Worlds.Sum(w => w.Characters.Count)} profiles {scan.Profiles.Count} shared {string.Join(",", scan.SharedFolders)}");
                        foreach (var w in scan.Worlds) Out($"  world {w.Name}: {w.Characters.Count}");
                        Out($"db pvars {scan.PersistentVariables} gvars {scan.GlobalVariables} quests {scan.QuestFlags}");
                        foreach (var n in scan.Notes) Out("note " + n);
                        return 0;
                    }
                    case "--import":
                    {
                        var scan = RetailImporter.Scan(Require(args, 1));
                        var target = Target(Require(args, 2));
                        var worldsArg = args.FirstOrDefault(a => a.StartsWith("--worlds=", StringComparison.Ordinal));
                        var worlds = worldsArg?.Substring(9).Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries).ToList();
                        foreach (var n in RetailImporter.Import(scan, target, Out, worlds).Distinct()) Out("note " + n);
                        return 0;
                    }
                    case "--install":
                    {
                        var target = Target(Require(args, 1));
                        var latest = ReleaseFeed.GetLatestAsync(Arg(args, 2) ?? "stable").GetAwaiter().GetResult();
                        var zip = Path.Combine(target.ManagerWorkDir, "download", latest.Plugin.File ?? "utilitybelt.zip");
                        try
                        {
                            Net.DownloadVerifiedAsync(latest.Plugin.Url, zip, latest.Plugin.Sha256, latest.Plugin.Size).GetAwaiter().GetResult();
                            Out("checksum verified");
                            PluginInstaller.InstallFromZip(target, zip, Out);
                        }
                        finally { if (File.Exists(zip)) File.Delete(zip); }
                        return 0;
                    }
                    case "--thwarg-import":
                    {
                        // --thwarg-import <ThwargLauncher folder | default> <client folder> [--no-passwords] [--dry-run]
                        var folder = Require(args, 1);
                        if (folder == "default") folder = ThwargImporter.DefaultFolder;
                        var target = Target(Require(args, 2));
                        var r = ThwargImporter.Import(folder, target, !args.Contains("--no-passwords"), args.Contains("--dry-run"));
                        Out($"{(args.Contains("--dry-run") ? "dry run: would add" : "added")} servers {r.ServersAdded} (existing {r.ServersSkipped}, invalid {r.ServersInvalid}), accounts {r.AccountsAdded} (existing {r.AccountsSkipped}) -> {r.LoginFile}");
                        if (r.Backup != null) Out("backup " + r.Backup);
                        foreach (var n in r.Notes) Out("note " + n);
                        return 0;
                    }
                    case "--rollback":
                        PluginInstaller.Rollback(Target(Require(args, 1)), Out);
                        return 0;
                    case "--uninstall":
                        PluginInstaller.Uninstall(Target(Require(args, 1)), args.Contains("--all"), Out);
                        return 0;
                    default:
                        Out("Unknown command " + args[0]);
                        return 2;
                }
            }
            catch (Exception ex)
            {
                Out("error " + ex.Message);
                return 1;
            }
            finally { file?.Dispose(); }
        }

        private static string Arg(string[] a, int i) => a.Length > i ? a[i] : null;
        private static string Require(string[] a, int i) => Arg(a, i) ?? throw new ArgumentException("Missing argument " + i);

        private static ClientTarget Target(string folder) =>
            ClientLocator.FromFolder(folder) ?? new ClientTarget { Label = "Custom", ClientPluginsDir = Path.GetFullPath(folder) };
    }
}
