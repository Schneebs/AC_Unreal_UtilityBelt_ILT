using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;

namespace UBManager
{
    /// <summary>Replaces UBManager.exe with a verified newer build, and installs it per user.</summary>
    internal static class SelfUpdater
    {
        private static string ExePath => Assembly.GetExecutingAssembly().Location;
        public static string InstalledExePath => Path.Combine(Program.DataDirectory, "UBManager.exe");

        public static bool IsNewer(ReleaseAsset manager) =>
            manager != null && !string.IsNullOrEmpty(manager.Version) && PluginInstaller.CompareVersions(manager.Version, Program.Version) > 0;

        /// <summary>
        /// Windows allows renaming a running exe: move the current one aside, put the
        /// verified download in its place, restart, and delete the old file next launch.
        /// </summary>
        public static async Task UpdateAndRestartAsync(ReleaseAsset manager)
        {
            var exe = ExePath;
            var download = exe + ".download";
            await Net.DownloadVerifiedAsync(manager.Url, download, manager.Sha256, manager.Size).ConfigureAwait(true);
            var old = exe + ".old";
            if (File.Exists(old)) File.Delete(old);
            File.Move(exe, old);
            try { File.Move(download, exe); }
            catch { File.Move(old, exe); throw; }
            Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true });
            Environment.Exit(0);
        }

        public static void CleanUpAfterUpdate()
        {
            try
            {
                foreach (var f in new[] { ExePath + ".old", ExePath + ".download" })
                    if (File.Exists(f)) File.Delete(f);
            }
            catch { /* the old process may still be exiting; try again next launch */ }
        }

        public static bool IsRunningFromInstalledLocation =>
            string.Equals(Path.GetFullPath(ExePath), Path.GetFullPath(InstalledExePath), StringComparison.OrdinalIgnoreCase);

        /// <summary>Copies the exe to %LOCALAPPDATA%\UBManager and adds a Start menu shortcut.</summary>
        public static void InstallForUser()
        {
            if (!IsRunningFromInstalledLocation) File.Copy(ExePath, InstalledExePath, true);
            var programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
            var link = Path.Combine(programs, "UB Manager.lnk");
            var shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null) return;
            dynamic shell = Activator.CreateInstance(shellType);
            try
            {
                dynamic shortcut = shell.CreateShortcut(link);
                shortcut.TargetPath = InstalledExePath;
                shortcut.WorkingDirectory = Program.DataDirectory;
                shortcut.Description = "Install and update UtilityBelt for AC:Unreal";
                shortcut.Save();
            }
            finally { System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shell); }
        }
    }
}
