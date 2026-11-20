using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Xml.Linq;

namespace UBManager
{
    internal sealed class ThwargServer
    {
        public string Name, Host, Description, Website, Discord;
        public int Port;
        public bool Gdle;
    }

    internal sealed class ThwargAccount
    {
        public string Username, Alias;
        public string Password;   // never logged or displayed
    }

    internal sealed class ThwargImportResult
    {
        public int ServersAdded, ServersSkipped, AccountsAdded, AccountsSkipped, ServersInvalid;
        public string LoginFile, Backup;
        public List<string> Notes = new List<string>();
    }

    /// <summary>
    /// Copies ThwargLauncher's servers and accounts into an AC:Unreal client's saved logins
    /// (Saved\Login\LastLogin.dat: JSON v3 protected with Windows DPAPI for the current user).
    /// Existing AC:Unreal entries are kept; duplicates are skipped; the old file is backed up.
    /// ThwargLauncher formats: Accounts.txt (Version=2; Name=..,Password=..,Alias=..; ^c ^e ^u
    /// escapes) and Servers\UserServerList.xml (ServerItem: name, emu, connect_string host:port).
    /// </summary>
    internal static class ThwargImporter
    {
        private const int MaxServers = 128, MaxAccounts = 512, MaxFileBytes = 524288;

        public static string DefaultFolder =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ThwargLauncher");

        public static string LoginFileFor(ClientTarget target) =>
            Path.Combine(Directory.GetParent(target.ClientPluginsDir).FullName, "Login", "LastLogin.dat");

        public static List<ThwargServer> ReadServers(string folder, List<string> notes)
        {
            var result = new List<ThwargServer>();
            var path = Path.Combine(folder, "Servers", "UserServerList.xml");
            if (!File.Exists(path)) { notes.Add("No ThwargLauncher server list found at " + path); return result; }
            foreach (var item in XDocument.Load(path).Descendants("ServerItem"))
            {
                string V(string n) => (string)item.Element(n) ?? "";
                var name = V("name").Trim();
                var connect = V("connect_string").Trim();
                var colon = connect.LastIndexOf(':');
                int port;
                if (string.IsNullOrEmpty(name) || colon <= 0 || !int.TryParse(connect.Substring(colon + 1), NumberStyles.Integer, CultureInfo.InvariantCulture, out port))
                { notes.Add($"Skipped server \"{name}\": no usable host:port."); continue; }
                result.Add(new ThwargServer
                {
                    Name = name.Length > 100 ? name.Substring(0, 100) : name,
                    Host = connect.Substring(0, colon).Trim(),
                    Port = port,
                    Gdle = !string.Equals(V("emu"), "ACE", StringComparison.OrdinalIgnoreCase),
                    Description = V("description"),
                    Website = WebLink(V("website_url")),
                    Discord = WebLink(V("discord_url")),
                });
            }
            return result;
        }

        public static List<ThwargAccount> ReadAccounts(string folder, List<string> notes)
        {
            var result = new List<ThwargAccount>();
            var path = Path.Combine(folder, "Accounts.txt");
            if (!File.Exists(path)) { notes.Add("No ThwargLauncher Accounts.txt found."); return result; }
            var sawVersion = false;
            foreach (var raw in File.ReadAllLines(path))
            {
                var line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#") || line.StartsWith("'")) continue;
                if (!sawVersion)
                {
                    if (!line.StartsWith("Version=2")) throw new InvalidDataException("Unsupported ThwargLauncher Accounts.txt (expected Version=2).");
                    sawVersion = true;
                    continue;
                }
                var set = new Dictionary<string, string>(StringComparer.Ordinal);
                foreach (var pair in line.Split(','))
                {
                    var eq = pair.IndexOf('=');
                    if (eq <= 0) continue;
                    set[Decode(pair.Substring(0, eq))] = Decode(pair.Substring(eq + 1));
                }
                if (!set.TryGetValue("Name", out var name) || string.IsNullOrEmpty(name) || !set.TryGetValue("Password", out var password)) continue;
                set.TryGetValue("Alias", out var alias);
                result.Add(new ThwargAccount { Username = name, Password = password ?? "", Alias = alias ?? "" });
            }
            return result;
        }

        private static string Decode(string text) => text.Replace("^e", "=").Replace("^c", ",").Replace("^u", "^");

        private static string WebLink(string url) =>
            !string.IsNullOrEmpty(url) && url.Length <= 2048 && (url.StartsWith("https://") || url.StartsWith("http://")) && url.IndexOfAny(new[] { '\r', '\n' }) < 0 ? url : "";

        /// <summary>
        /// The client keeps its logins in memory and rewrites the file, so the client that owns
        /// this Saved folder must be closed. Returns the blocking process name, or null.
        /// Unreadable process paths count as blocking.
        /// </summary>
        public static string RunningClient(ClientTarget target)
        {
            // <root>\ACUnreal\Saved\ClientPlugins (installed or packaged) or <repo>\Unreal\Saved\ClientPlugins (source).
            var saved = Directory.GetParent(target.ClientPluginsDir).FullName;
            var root = Directory.GetParent(Directory.GetParent(saved).FullName)?.FullName ?? saved;
            var sourceBuild = File.Exists(Path.Combine(Directory.GetParent(saved).FullName, "ACUnreal.uproject"));
            foreach (var name in new[] { "ACUnreal", "ACUnreal-Win64-Shipping", "ACUnreal-Win64-Development", "UnrealEditor" })
            {
                foreach (var p in Process.GetProcessesByName(name))
                {
                    if (name == "UnrealEditor") { if (sourceBuild) return name; continue; }
                    string path;
                    try { path = p.MainModule.FileName; } catch { return name; }
                    if (path.StartsWith(root.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase)) return name;
                }
            }
            return null;
        }

        public static ThwargImportResult Import(string thwargFolder, ClientTarget target, bool includePasswords, bool dryRun)
        {
            var result = new ThwargImportResult { LoginFile = LoginFileFor(target) };
            if (!dryRun)
            {
                var running = RunningClient(target);
                if (running != null) throw new InvalidOperationException($"Close AC:Unreal ({running}) first: it rewrites its saved logins when it exits.");
            }

            var servers = ReadServers(thwargFolder, result.Notes);
            var accounts = ReadAccounts(thwargFolder, result.Notes);

            Dictionary<string, object> doc;
            if (File.Exists(result.LoginFile))
            {
                var plain = ProtectedData.Unprotect(File.ReadAllBytes(result.LoginFile), null, DataProtectionScope.CurrentUser);
                doc = Json.ParseObject(Encoding.UTF8.GetString(plain));
                if (doc.TryGetValue("version", out var v) && v != null && Convert.ToDouble(v, CultureInfo.InvariantCulture) != 2 && Convert.ToDouble(v, CultureInfo.InvariantCulture) != 3)
                    throw new InvalidDataException("Unrecognized AC:Unreal login file version " + v + "; nothing was changed.");
            }
            else
            {
                doc = new Dictionary<string, object>
                {
                    ["host"] = "", ["port"] = "9000", ["account"] = "", ["password"] = "",
                    ["savePasswordsLocally"] = false, ["selectedServer"] = "", ["selectedAccount"] = "",
                    ["datDirectory"] = "", ["autoUpdate"] = false,
                };
            }
            doc["version"] = 3;
            // Fields the loader requires even in the profile format.
            foreach (var key in new[] { "host", "account", "password" }) if (!doc.ContainsKey(key) || doc[key] == null) doc[key] = "";
            if (!doc.ContainsKey("port") || doc["port"] == null) doc["port"] = "9000";

            var serverList = (doc.TryGetValue("servers", out var s) && s is object[] sa ? sa : new object[0]).OfType<Dictionary<string, object>>().ToList();
            var accountList = (doc.TryGetValue("accounts", out var a) && a is object[] aa ? aa : new object[0]).OfType<Dictionary<string, object>>().ToList();

            foreach (var server in servers)
            {
                if (server.Host.Length == 0 || server.Host.Length > 253 || server.Host.IndexOfAny(new[] { ':', '/', '\\', '@', '?', '#', ' ', '\t' }) >= 0 || server.Port < 1 || server.Port > 65534)
                { result.ServersInvalid++; result.Notes.Add($"Skipped server \"{server.Name}\": host or port not accepted by AC:Unreal."); continue; }
                var exists = serverList.Any(e =>
                    string.Equals(Json.Get(e, "host"), server.Host, StringComparison.OrdinalIgnoreCase) &&
                    Json.Get(e, "port") == server.Port.ToString(CultureInfo.InvariantCulture));
                if (exists) { result.ServersSkipped++; continue; }
                if (serverList.Count >= MaxServers) { result.Notes.Add("AC:Unreal holds at most 128 servers; the rest were skipped."); break; }
                serverList.Add(new Dictionary<string, object>
                {
                    ["id"] = NewId(), ["name"] = server.Name, ["host"] = server.Host, ["port"] = server.Port,
                    ["gdle"] = server.Gdle, ["description"] = server.Description ?? "",
                    ["website"] = server.Website ?? "", ["discord"] = server.Discord ?? "",
                });
                result.ServersAdded++;
            }

            foreach (var account in accounts)
            {
                var exists = accountList.Any(e => string.Equals(Json.Get(e, "username"), account.Username, StringComparison.OrdinalIgnoreCase));
                if (exists) { result.AccountsSkipped++; continue; }
                if (accountList.Count >= MaxAccounts) { result.Notes.Add("AC:Unreal holds at most 512 accounts; the rest were skipped."); break; }
                accountList.Add(new Dictionary<string, object>
                {
                    ["id"] = NewId(), ["alias"] = account.Alias ?? "", ["username"] = account.Username,
                    ["password"] = includePasswords ? account.Password : "",
                });
                result.AccountsAdded++;
            }

            doc["servers"] = serverList;
            doc["accounts"] = accountList;
            if (string.IsNullOrEmpty(Json.Get(doc, "selectedServer")) && serverList.Count > 0) doc["selectedServer"] = Json.Get(serverList[0], "id");

            var bytes = Encoding.UTF8.GetBytes(Json.Stringify(doc));
            if (bytes.Length > MaxFileBytes) throw new InvalidDataException("The combined login list is larger than AC:Unreal accepts (512 KiB); nothing was changed.");
            if (dryRun || result.ServersAdded + result.AccountsAdded == 0) return result;   // nothing new: leave the file alone

            Directory.CreateDirectory(Path.GetDirectoryName(result.LoginFile));
            if (File.Exists(result.LoginFile))
            {
                result.Backup = result.LoginFile + ".ubmanager-backup-" + DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
                File.Copy(result.LoginFile, result.Backup);
            }
            var protectedBytes = ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser);
            Array.Clear(bytes, 0, bytes.Length);
            var tmp = result.LoginFile + ".ubmanager-tmp";
            File.WriteAllBytes(tmp, protectedBytes);
            if (File.Exists(result.LoginFile)) File.Replace(tmp, result.LoginFile, null);
            else File.Move(tmp, result.LoginFile);
            return result;
        }

        // Matches the client's FGuid::ToString() form: 32 upper-case hex digits.
        private static string NewId() => Guid.NewGuid().ToString("N").ToUpperInvariant();
    }
}
