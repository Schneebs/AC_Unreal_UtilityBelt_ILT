using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace UBManager
{
    internal sealed class MainForm : Form
    {
        private readonly Config config = Config.Load();
        private ReleaseInfo latest;

        private readonly ComboBox clients = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
        private readonly ComboBox channel = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 110 };
        private readonly Label installedLabel = new Label { AutoSize = true };
        private readonly Label latestLabel = new Label { AutoSize = true };
        private readonly Button installButton = new Button { Text = "Install", AutoSize = true };
        private readonly Button rollbackButton = new Button { Text = "Roll back", AutoSize = true };
        private readonly Button uninstallButton = new Button { Text = "Uninstall…", AutoSize = true };
        private readonly Button checkButton = new Button { Text = "Check for updates", AutoSize = true };
        private readonly TextBox retailFolder = new TextBox { Dock = DockStyle.Fill };
        private readonly Button previewButton = new Button { Text = "Preview", AutoSize = true };
        private readonly Button importButton = new Button { Text = "Import", AutoSize = true };
        private readonly CheckedListBox worldList = new CheckedListBox { Dock = DockStyle.Fill, Height = 110, CheckOnClick = true, IntegralHeight = false };
        private readonly TextBox log = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font(FontFamily.GenericMonospace, 9f) };
        private readonly Button selfUpdateButton = new Button { Text = "Update UB Manager", AutoSize = true, Visible = false };
        private readonly Button installSelfButton = new Button { Text = "Install UB Manager for this user", AutoSize = true };
        private RetailScan lastScan;

        public MainForm()
        {
            Text = "UB Manager " + Program.Version + " — UtilityBelt for AC:Unreal";
            Font = SystemFonts.MessageBoxFont;
            ClientSize = new Size(760, 600);
            MinimumSize = new Size(640, 520);
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Dpi;

            var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(10), ColumnCount = 1, RowCount = 5 };
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Controls.Add(root);

            // AC:Unreal client
            var clientBox = Group("AC:Unreal client");
            var clientRow = Row();
            var addFolder = new Button { Text = "Add folder…", AutoSize = true };
            var openPlugins = new Button { Text = "Open plugin folder", AutoSize = true };
            clientRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            clientRow.Controls.Add(clients, 0, 0);
            clientRow.Controls.Add(addFolder, 1, 0);
            clientRow.Controls.Add(openPlugins, 2, 0);
            clientBox.Controls.Add(clientRow);
            root.Controls.Add(clientBox);

            // Plugin
            var pluginBox = Group("UtilityBelt plugin");
            var pluginRows = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false };
            var versions = new FlowLayoutPanel { AutoSize = true };
            versions.Controls.Add(installedLabel);
            versions.Controls.Add(new Label { Text = "   ", AutoSize = true });
            versions.Controls.Add(latestLabel);
            var actions = new FlowLayoutPanel { AutoSize = true };
            actions.Controls.Add(new Label { Text = "Channel:", AutoSize = true, Padding = new Padding(0, 6, 0, 0) });
            actions.Controls.Add(channel);
            actions.Controls.AddRange(new Control[] { checkButton, installButton, rollbackButton, uninstallButton });
            pluginRows.Controls.Add(versions);
            pluginRows.Controls.Add(actions);
            pluginBox.Controls.Add(pluginRows);
            root.Controls.Add(pluginBox);

            // Retail import
            var retailBox = Group("Retail UtilityBelt data (read only; nothing in it is changed)");
            var retailRow = Row();
            var browse = new Button { Text = "Browse…", AutoSize = true };
            retailRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            retailRow.Controls.Add(retailFolder, 0, 0);
            retailRow.Controls.Add(browse, 1, 0);
            retailRow.Controls.Add(previewButton, 2, 0);
            retailRow.Controls.Add(importButton, 3, 0);
            retailRow.RowCount = 2;
            retailRow.Controls.Add(worldList, 0, 1);
            retailRow.SetColumnSpan(worldList, 4);
            retailBox.Controls.Add(retailRow);
            root.Controls.Add(retailBox);

            root.Controls.Add(log);

            var footer = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
            footer.Controls.AddRange(new Control[] { installSelfButton, selfUpdateButton });
            root.Controls.Add(footer);

            channel.Items.AddRange(new object[] { "Stable", "Beta" });
            channel.SelectedIndex = config.Channel == "beta" ? 1 : 0;
            retailFolder.Text = string.IsNullOrEmpty(config.RetailFolder) ? RetailImporter.DefaultRoot : config.RetailFolder;
            installSelfButton.Visible = !SelfUpdater.IsRunningFromInstalledLocation;

            clients.SelectedIndexChanged += (s, e) => { config.SelectedClient = Selected?.ClientPluginsDir; config.Save(); RefreshInstalled(); };
            addFolder.Click += (s, e) => AddFolder();
            openPlugins.Click += (s, e) => { var t = Selected; if (t != null) { Directory.CreateDirectory(t.InstalledDir); Process.Start("explorer.exe", t.InstalledDir); } };
            channel.SelectedIndexChanged += async (s, e) => { config.Channel = channel.SelectedIndex == 1 ? "beta" : "stable"; config.Save(); await CheckAsync(); };
            checkButton.Click += async (s, e) => await CheckAsync();
            installButton.Click += async (s, e) => await InstallAsync();
            rollbackButton.Click += (s, e) => Run(() => { PluginInstaller.Rollback(Selected, Log); Log("Press Refresh in the in-game Plugin Manager to load it."); });
            uninstallButton.Click += (s, e) => Uninstall();
            browse.Click += (s, e) => BrowseRetail();
            previewButton.Click += (s, e) => Preview();
            importButton.Click += (s, e) => Import();
            selfUpdateButton.Click += async (s, e) => await SelfUpdateAsync();
            installSelfButton.Click += (s, e) => Run(() => { SelfUpdater.InstallForUser(); Log("UB Manager installed to " + SelfUpdater.InstalledExePath + " with a Start menu shortcut."); installSelfButton.Visible = false; });

            Shown += async (s, e) => { LoadClients(); await CheckAsync(); };
        }

        private ClientTarget Selected => clients.SelectedItem as ClientTarget;

        private static GroupBox Group(string text) =>
            new GroupBox { Text = text, Dock = DockStyle.Fill, AutoSize = true, Padding = new Padding(8) };

        private static TableLayoutPanel Row() =>
            new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 4, RowCount = 1 };

        private void Log(string line)
        {
            if (InvokeRequired) { BeginInvoke(new Action<string>(Log), line); return; }
            log.AppendText(DateTime.Now.ToString("HH:mm:ss") + "  " + line + Environment.NewLine);
        }

        private void Run(Action action)
        {
            try { action(); }
            catch (Exception ex) { Log("Error: " + ex.Message); }
            RefreshInstalled();
        }

        private void LoadClients()
        {
            var found = ClientLocator.Find(config.ExtraClientFolders);
            clients.Items.Clear();
            foreach (var t in found) clients.Items.Add(t);
            var keep = found.FirstOrDefault(t => config.SelectedClient != null && ClientLocator.SamePath(t.ClientPluginsDir, config.SelectedClient));
            if (keep != null) clients.SelectedItem = keep;
            else if (found.Count > 0) clients.SelectedIndex = 0;
            if (found.Count == 0) Log("No AC:Unreal client found. Install the client, or use Add folder… for a source build.");
            RefreshInstalled();
        }

        private void AddFolder()
        {
            using (var dialog = new FolderBrowserDialog { Description = "Choose the AC:Unreal source checkout, its Unreal folder, or a ClientPlugins folder" })
            {
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                var target = ClientLocator.FromFolder(dialog.SelectedPath);
                if (target == null) { Log("That folder is not an AC:Unreal client or source build."); return; }
                if (!config.ExtraClientFolders.Any(f => ClientLocator.SamePath(f, dialog.SelectedPath))) config.ExtraClientFolders.Add(dialog.SelectedPath);
                config.SelectedClient = target.ClientPluginsDir;
                config.Save();
                LoadClients();
            }
        }

        private void RefreshInstalled()
        {
            var t = Selected;
            var installed = t == null ? null : PluginInstaller.InstalledVersion(t);
            var isLink = t != null && PluginInstaller.IsLink(t.PluginDir(PluginInstaller.PluginId));
            installedLabel.Text = "Installed: " + (installed ?? "not installed") + (isLink ? " (developer link)" : "");
            latestLabel.Text = "Latest: " + (latest == null ? "unknown" : latest.Version + " (" + (latest.Channel ?? config.Channel) + ")");
            var updateAvailable = latest != null && PluginInstaller.CompareVersions(latest.Version, installed) > 0;
            installButton.Text = installed == null ? "Install" : updateAvailable ? "Update to " + latest.Version : "Reinstall";
            installButton.Enabled = t != null && latest != null && !isLink;
            rollbackButton.Enabled = t != null && !isLink && PluginInstaller.BackupVersion(t) != null;
            uninstallButton.Enabled = t != null && !isLink && installed != null;
            importButton.Enabled = t != null && lastScan != null;
            selfUpdateButton.Visible = latest != null && SelfUpdater.IsNewer(latest.Manager);
            if (selfUpdateButton.Visible) selfUpdateButton.Text = "Update UB Manager to " + latest.Manager.Version;
        }

        private async Task CheckAsync()
        {
            checkButton.Enabled = false;
            try
            {
                latest = await ReleaseFeed.GetLatestAsync(config.Channel);
                Log($"Latest {config.Channel} release: {latest.Version}.");
            }
            catch (Exception ex) { latest = null; Log("Could not check for updates: " + ex.Message); }
            finally { checkButton.Enabled = true; RefreshInstalled(); }
        }

        private async Task InstallAsync()
        {
            var t = Selected;
            if (t == null || latest == null) return;
            installButton.Enabled = false;
            var zip = Path.Combine(t.ManagerWorkDir, "download", latest.Plugin.File ?? "utilitybelt.zip");
            try
            {
                Log("Downloading " + latest.Plugin.File + "…");
                await Net.DownloadVerifiedAsync(latest.Plugin.Url, zip, latest.Plugin.Sha256, latest.Plugin.Size);
                Log("Checksum verified.");
                PluginInstaller.InstallFromZip(t, zip, Log);
                Log("If the game is running, press Refresh in the in-game Plugin Manager (/acueplugins).");
            }
            catch (Exception ex) { Log("Install failed, nothing was changed: " + ex.Message); }
            finally
            {
                try { if (File.Exists(zip)) File.Delete(zip); } catch { }
                RefreshInstalled();
            }
        }

        private void Uninstall()
        {
            var t = Selected;
            if (t == null) return;
            var answer = MessageBox.Show(this,
                "Remove UtilityBelt from this client?\n\nYes: remove the plugin and keep its saved settings.\nNo: remove the plugin and its saved settings and imports.\nCancel: do nothing.",
                "Uninstall UtilityBelt", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question, MessageBoxDefaultButton.Button1);
            if (answer == DialogResult.Cancel) return;
            Run(() => PluginInstaller.Uninstall(t, answer == DialogResult.No, Log));
        }

        private void BrowseRetail()
        {
            using (var dialog = new FolderBrowserDialog { Description = "Choose the retail UtilityBelt folder (Documents\\Decal Plugins\\UtilityBelt)", SelectedPath = retailFolder.Text })
            {
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                retailFolder.Text = dialog.SelectedPath;
                config.RetailFolder = dialog.SelectedPath;
                config.Save();
            }
        }

        private void Preview()
        {
            Run(() =>
            {
                lastScan = RetailImporter.Scan(retailFolder.Text.Trim());
                var chars = lastScan.Worlds.Sum(w => w.Characters.Count);
                Log($"Found {lastScan.Worlds.Count} worlds with {chars} characters, {lastScan.Profiles.Count} named profiles, shared folders: {(lastScan.SharedFolders.Count == 0 ? "none" : string.Join(", ", lastScan.SharedFolders))}.");
                worldList.Items.Clear();
                foreach (var w in lastScan.Worlds)
                {
                    Log($"  {w.Name}: {w.Characters.Count} characters");
                    worldList.Items.Add(new WorldItem(w), true);
                }
                Log("Untick worlds you don't want imported (large worlds take longer).");
                if (lastScan.DatabasePath != null)
                    Log($"Database: {lastScan.PersistentVariables} persistent variables, {lastScan.GlobalVariables} global variables, {lastScan.QuestFlags} quest flags.");
                foreach (var n in lastScan.Notes) Log("Note: " + n);
                Log("Press Import to copy this into the plugin's profile library. Retail files are not changed.");
            });
        }

        private void Import()
        {
            var t = Selected;
            if (t == null || lastScan == null) return;
            var selected = worldList.CheckedItems.OfType<WorldItem>().Select(w => w.World.Name).ToList();
            if (selected.Count == 0) { Log("Tick at least one world to import."); return; }
            Cursor = Cursors.WaitCursor;
            Run(() =>
            {
                var notes = RetailImporter.Import(lastScan, t, Log, selected);
                foreach (var n in notes.Distinct().Take(50)) Log("Note: " + n);
                if (notes.Count > 50) Log($"…and {notes.Count - 50} more notes.");
                Log("In game, open UtilityBelt and press Import from retail on each character to apply its settings.");
            });
            Cursor = Cursors.Default;
        }

        private sealed class WorldItem
        {
            public readonly RetailWorld World;
            public WorldItem(RetailWorld w) { World = w; }
            public override string ToString() => $"{World.Name}  ({World.Characters.Count:N0} characters)";
        }

        private async Task SelfUpdateAsync()
        {
            if (latest?.Manager == null) return;
            selfUpdateButton.Enabled = false;
            try
            {
                Log("Downloading UB Manager " + latest.Manager.Version + "…");
                await SelfUpdater.UpdateAndRestartAsync(latest.Manager);
            }
            catch (Exception ex) { Log("UB Manager update failed, nothing was changed: " + ex.Message); selfUpdateButton.Enabled = true; }
        }
    }
}
