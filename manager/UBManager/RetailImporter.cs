using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using LiteDB;

namespace UBManager
{
    internal sealed class RetailCharacter
    {
        public string Name, Dir;
        public List<string> Files = new List<string>();
    }

    internal sealed class RetailWorld
    {
        public string Name, Dir;
        public List<RetailCharacter> Characters = new List<RetailCharacter>();
    }

    internal sealed class RetailScan
    {
        public string Root, DatabasePath;
        public List<RetailWorld> Worlds = new List<RetailWorld>();
        public List<string> Profiles = new List<string>();          // named profile base names
        public List<string> SharedFolders = new List<string>();
        public int PersistentVariables, GlobalVariables, QuestFlags;
        public List<string> Notes = new List<string>();
    }

    /// <summary>
    /// Reads retail UtilityBelt data (never writes to it) and writes it into the plugin's
    /// profile library: ClientPlugins\Profiles\utilitybelt\Library\r_*\*.json.
    /// Every top-level key is prefixed ub_ so it never collides with UCM profile keys
    /// that the client validates.
    /// </summary>
    internal static class RetailImporter
    {
        public const string IndexGroup = "r_index";
        public const string ProfilesGroup = "r_profiles";
        public const string SharedGroup = "r_shared";
        private const int ReadLimitBytes = 256 * 1024;     // client returns at most 256 KiB per read
        private static readonly string[] CharacterFiles = { "settings.json", "state.json", "aliases.json", "events.json" };
        private static readonly string[] SharedFolderNames = { "autovendor", "autotrade", "equip", "itemgiver", "packsorter", "summons" };
        private static readonly HashSet<string> NotWorlds = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            { "profiles", "scripts", "scriptdata", "docs", "logs", "autovendor", "autotrade", "equip", "itemgiver", "packsorter", "summons" };

        public static string DefaultRoot =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Decal Plugins", "UtilityBelt");

        public static RetailScan Scan(string root)
        {
            var scan = new RetailScan { Root = root };
            if (!Directory.Exists(root)) { scan.Notes.Add("Retail UtilityBelt folder not found: " + root); return scan; }

            foreach (var worldDir in Directory.GetDirectories(root).OrderBy(d => d, StringComparer.OrdinalIgnoreCase))
            {
                var worldName = Path.GetFileName(worldDir);
                if (NotWorlds.Contains(worldName)) continue;
                var world = new RetailWorld { Name = worldName, Dir = worldDir };
                foreach (var charDir in SafeDirectories(worldDir))
                {
                    // Any JSON counts: ILT tools keep extra per-character files (bankbalances.json, itemconversions.json).
                    List<string> files;
                    try { files = Directory.GetFiles(charDir, "*.json").Select(Path.GetFileName).OrderBy(f => f).ToList(); }
                    catch { continue; }
                    if (files.Count > 0) world.Characters.Add(new RetailCharacter { Name = Path.GetFileName(charDir), Dir = charDir, Files = files });
                }
                if (world.Characters.Count > 0) scan.Worlds.Add(world);
            }

            var profilesDir = Path.Combine(root, "profiles");
            if (Directory.Exists(profilesDir))
                scan.Profiles = Directory.GetFiles(profilesDir, "*.json")
                    .Select(f => Path.GetFileName(f))
                    .Select(f => f.EndsWith(".settings.json") ? f.Substring(0, f.Length - 14)
                               : f.EndsWith(".aliases.json") ? f.Substring(0, f.Length - 13)
                               : f.EndsWith(".events.json") ? f.Substring(0, f.Length - 12) : null)
                    .Where(n => !string.IsNullOrEmpty(n)).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(n => n).ToList();

            scan.SharedFolders = SharedFolderNames.Where(n => Directory.Exists(Path.Combine(root, n))).ToList();

            var db = Path.Combine(root, "utilitybelt.db");
            if (File.Exists(db))
            {
                scan.DatabasePath = db;
                try
                {
                    WithDatabaseCopy(db, ldb =>
                    {
                        scan.PersistentVariables = ldb.GetCollection("persistent_variables").Count();
                        scan.GlobalVariables = ldb.GetCollection("global_variables").Count();
                        scan.QuestFlags = ldb.GetCollection("quest_flags").Count();
                    });
                }
                catch (Exception ex) { scan.Notes.Add("Could not read utilitybelt.db: " + ex.Message); }
            }
            return scan;
        }

        private static IEnumerable<string> SafeDirectories(string dir)
        {
            try { return Directory.GetDirectories(dir).OrderBy(d => d, StringComparer.OrdinalIgnoreCase); }
            catch { return Enumerable.Empty<string>(); }
        }

        /// <summary>
        /// Writes the scan into the library. Replaces only UB Manager's own r_* groups.
        /// <paramref name="worlds"/> limits which worlds are imported (null = all).
        /// </summary>
        public static List<string> Import(RetailScan scan, ClientTarget target, Action<string> log, ICollection<string> worlds = null)
        {
            var notes = new List<string>(scan.Notes.Where(n => !n.StartsWith("Could not read utilitybelt.db", StringComparison.Ordinal)));
            bool Wanted(string world) => worlds == null || worlds.Contains(world, StringComparer.OrdinalIgnoreCase);
            var library = target.LibraryDir(PluginInstaller.PluginId);
            Directory.CreateDirectory(library);
            foreach (var old in Directory.GetDirectories(library, "r_*")) Directory.Delete(old, true);

            // Database rows, grouped by server (world) and character.
            var pvars = new Dictionary<string, Dictionary<string, Dictionary<string, object>>>(StringComparer.OrdinalIgnoreCase);
            var gvars = new Dictionary<string, Dictionary<string, object>>(StringComparer.OrdinalIgnoreCase);
            var quests = new Dictionary<string, Dictionary<string, List<object>>>(StringComparer.OrdinalIgnoreCase);
            if (scan.DatabasePath != null)
            {
                try
                {
                    WithDatabaseCopy(scan.DatabasePath, ldb =>
                    {
                        foreach (var d in ldb.GetCollection("persistent_variables").FindAll())
                            Bucket(Bucket(pvars, S(d, "Server")), S(d, "Character"))[S(d, "Name")] =
                                new Dictionary<string, object> { ["type"] = S(d, "Type"), ["value"] = S(d, "Value") };
                        foreach (var d in ldb.GetCollection("global_variables").FindAll())
                            Bucket(gvars, S(d, "Server"))[S(d, "Name")] =
                                new Dictionary<string, object> { ["type"] = S(d, "Type"), ["value"] = S(d, "Value") };
                        foreach (var d in ldb.GetCollection("quest_flags").FindAll())
                        {
                            var byChar = quests.TryGetValue(S(d, "Server"), out var q) ? q : quests[S(d, "Server")] = new Dictionary<string, List<object>>(StringComparer.OrdinalIgnoreCase);
                            var list = byChar.TryGetValue(S(d, "Character"), out var l) ? l : byChar[S(d, "Character")] = new List<object>();
                            list.Add(new Dictionary<string, object>
                            {
                                ["key"] = S(d, "Key"), ["description"] = S(d, "Description"),
                                ["solves"] = d["Solves"].IsNumber ? d["Solves"].AsInt32 : 0,
                                ["max_solves"] = d["MaxSolves"].IsNumber ? d["MaxSolves"].AsInt32 : 0,
                                ["completed_on"] = d["CompletedOn"].IsDateTime ? (object)d["CompletedOn"].AsDateTime : null,
                                ["repeat_time"] = d["RepeatTime"].IsNumber ? d["RepeatTime"].AsInt32 : 0,
                            });
                        }
                    });
                }
                catch (Exception ex) { notes.Add("Variables and quests were skipped: utilitybelt.db could not be read (" + ex.Message + ")."); }
            }

            var worldIndex = new List<object>();
            var worldNames = scan.Worlds.Select(w => w.Name)
                .Concat(pvars.Keys).Concat(gvars.Keys).Concat(quests.Keys)
                .Where(n => !string.IsNullOrEmpty(n) && Wanted(n)).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(n => n).ToList();
            var characterCount = 0;
            foreach (var worldName in worldNames)
            {
                var group = "r_" + SafeName(worldName, 62);
                var dir = Path.Combine(library, group);
                var world = scan.Worlds.FirstOrDefault(w => string.Equals(w.Name, worldName, StringComparison.OrdinalIgnoreCase));
                var characterNames = (world?.Characters.Select(c => c.Name) ?? Enumerable.Empty<string>())
                    .Concat(pvars.TryGetValue(worldName, out var pv) ? pv.Keys : Enumerable.Empty<string>())
                    .Concat(quests.TryGetValue(worldName, out var qv) ? qv.Keys : Enumerable.Empty<string>())
                    .Where(n => !string.IsNullOrEmpty(n)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();

                var characterMap = new SortedDictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                foreach (var name in characterNames)
                {
                    var file = SafeName(name, 64);
                    characterMap[name] = file;
                    var doc = new Dictionary<string, object>
                    {
                        ["ub_source"] = new Dictionary<string, object> { ["world"] = worldName, ["character"] = name, ["imported"] = DateTime.UtcNow },
                    };
                    var rc = world?.Characters.FirstOrDefault(c => string.Equals(c.Name, name, StringComparison.OrdinalIgnoreCase));
                    if (rc != null)
                    {
                        AddJsonFile(doc, "ub_settings", Path.Combine(rc.Dir, "settings.json"), notes);
                        AddJsonFile(doc, "ub_state", Path.Combine(rc.Dir, "state.json"), notes);
                        AddJsonFile(doc, "ub_aliases", Path.Combine(rc.Dir, "aliases.json"), notes);
                        AddJsonFile(doc, "ub_events", Path.Combine(rc.Dir, "events.json"), notes);
                        var extra = new SortedDictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                        foreach (var f in rc.Files.Where(f => !CharacterFiles.Contains(f, StringComparer.OrdinalIgnoreCase)))
                        {
                            var path = Path.Combine(rc.Dir, f);
                            try
                            {
                                if (new FileInfo(path).Length > ReadLimitBytes) { notes.Add($"{worldName}/{name}: {f} is over 256 KiB and was skipped."); continue; }
                                extra[f] = Json.Parse(File.ReadAllText(path, Encoding.UTF8));
                            }
                            catch (Exception ex) { notes.Add($"Skipped unreadable {worldName}/{name}/{f} ({ex.Message})"); }
                        }
                        if (extra.Count > 0) doc["ub_files"] = extra;
                    }
                    if (pv != null && pv.TryGetValue(name, out var vars)) doc["ub_pvars"] = vars;
                    if (qv != null && qv.TryGetValue(name, out var qs)) AddChunked(doc, "ub_quests", qs);
                    CheckSections(doc, worldName + "/" + name, notes);
                    Json.WriteFile(Path.Combine(dir, file + ".json"), doc);
                    characterCount++;
                }
                Json.WriteFile(Path.Combine(dir, "_index.json"), new Dictionary<string, object> { ["ub_world"] = worldName, ["ub_characters"] = characterMap });
                if (gvars.TryGetValue(worldName, out var g))
                    Json.WriteFile(Path.Combine(dir, "_globals.json"), new Dictionary<string, object> { ["ub_world"] = worldName, ["ub_gvars"] = g });
                worldIndex.Add(new Dictionary<string, object> { ["name"] = worldName, ["group"] = group, ["characters"] = characterMap.Count });
            }

            // Named shared profiles.
            var profileIndex = new List<object>();
            var profilesDir = Path.Combine(scan.Root, "profiles");
            foreach (var profile in scan.Profiles)
            {
                var file = SafeName(profile, 64);
                var doc = new Dictionary<string, object> { ["ub_profile"] = profile };
                AddJsonFile(doc, "ub_settings", Path.Combine(profilesDir, profile + ".settings.json"), notes);
                AddJsonFile(doc, "ub_aliases", Path.Combine(profilesDir, profile + ".aliases.json"), notes);
                AddJsonFile(doc, "ub_events", Path.Combine(profilesDir, profile + ".events.json"), notes);
                CheckSections(doc, "profile " + profile, notes);
                Json.WriteFile(Path.Combine(library, ProfilesGroup, file + ".json"), doc);
                profileIndex.Add(new Dictionary<string, object> { ["name"] = profile, ["file"] = file });
            }

            // Shared tool folders: JSON lists are embedded, other files (.utl) are listed.
            foreach (var folder in scan.SharedFolders)
            {
                var dir = Path.Combine(scan.Root, folder);
                var files = new List<object>();
                var lists = new Dictionary<string, object>();
                foreach (var f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories).OrderBy(x => x))
                {
                    var rel = f.Substring(dir.Length).TrimStart('\\').Replace('\\', '/');
                    var size = new FileInfo(f).Length;
                    files.Add(new Dictionary<string, object> { ["name"] = rel, ["size"] = size });
                    if (f.EndsWith(".json", StringComparison.OrdinalIgnoreCase) && size <= ReadLimitBytes)
                        try { lists[rel] = Json.Parse(File.ReadAllText(f, Encoding.UTF8)); } catch { notes.Add("Skipped unreadable " + folder + "/" + rel); }
                }
                Json.WriteFile(Path.Combine(library, SharedGroup, SafeName(folder, 64) + ".json"),
                    new Dictionary<string, object> { ["ub_folder"] = folder, ["ub_files"] = files, ["ub_lists"] = lists });
            }

            Json.WriteFile(Path.Combine(library, IndexGroup, "index.json"), new Dictionary<string, object>
            {
                ["ub_index"] = new Dictionary<string, object>
                {
                    ["format"] = 1,
                    ["generated"] = DateTime.UtcNow,
                    ["generator"] = "UB Manager " + Program.Version,
                    ["worlds"] = worldIndex,
                    ["profiles_group"] = ProfilesGroup,
                    ["profiles"] = profileIndex,
                    ["shared_group"] = SharedGroup,
                    ["shared"] = scan.SharedFolders,
                }
            });
            log?.Invoke($"Imported {worldNames.Count} worlds, {characterCount} characters, {scan.Profiles.Count} profiles and {scan.SharedFolders.Count} shared folders.");
            return notes;
        }

        private static void AddJsonFile(Dictionary<string, object> doc, string key, string path, List<string> notes)
        {
            if (!File.Exists(path)) return;
            try { doc[key] = Json.Parse(File.ReadAllText(path, Encoding.UTF8)); }
            catch (Exception ex) { notes.Add("Skipped unreadable " + path + " (" + ex.Message + ")"); }
        }

        /// <summary>
        /// Splits a long list into sections key_0, key_1, ... each under ~200 KiB of compact
        /// JSON, so the plugin can read every part within the client's 256 KiB read limit.
        /// key_parts holds the number of parts.
        /// </summary>
        private static void AddChunked(Dictionary<string, object> doc, string key, List<object> items)
        {
            const int Target = 200 * 1024;
            var part = new List<object>();
            var size = 2;
            var index = 0;
            foreach (var item in items)
            {
                var itemSize = Encoding.UTF8.GetByteCount(Compact(item)) + 1;
                if (part.Count > 0 && size + itemSize > Target)
                {
                    doc[key + "_" + index++] = part;
                    part = new List<object>();
                    size = 2;
                }
                part.Add(item);
                size += itemSize;
            }
            if (part.Count > 0 || index == 0) doc[key + "_" + index++] = part;
            doc[key + "_parts"] = index;
        }

        private static string Compact(object value) =>
            new System.Web.Script.Serialization.JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Serialize(value);

        private static void CheckSections(Dictionary<string, object> doc, string what, List<string> notes)
        {
            foreach (var kv in doc)
            {
                var bytes = Encoding.UTF8.GetByteCount(Compact(kv.Value));
                if (bytes > ReadLimitBytes)
                    notes.Add($"{what}: section {kv.Key} is {bytes / 1024} KiB, over the client's 256 KiB read limit; the plugin cannot load it whole.");
            }
        }

        /// <summary>
        /// Copies the database (and its LiteDB 5 log) and reads the copy. The original is only
        /// ever opened for reading. Running retail clients keep writing it, so a copy taken
        /// mid-write can be inconsistent: retry until the source is unchanged across the copy
        /// and the copy opens cleanly, then give up with a clear message.
        /// </summary>
        private static void WithDatabaseCopy(string db, Action<LiteDatabase> read)
        {
            var log = Path.ChangeExtension(db, null) + "-journal.db";     // LiteDB 4 journal, if a write is in progress
            Exception last = null;
            for (var attempt = 1; attempt <= 5; attempt++)
            {
                var copy = Path.Combine(Path.GetTempPath(), "ubmanager-" + Guid.NewGuid().ToString("N") + ".db");
                var copyLog = Path.ChangeExtension(copy, null) + "-journal.db";
                try
                {
                    var before = Stamp(db) + Stamp(log);
                    CopyShared(db, copy);
                    if (File.Exists(log)) CopyShared(log, copyLog);
                    if (Stamp(db) + Stamp(log) != before) throw new IOException("utilitybelt.db changed while it was being copied.");
                    // Exclusive access to the private copy; the journal (if copied) is applied to the copy only.
                    using (var ldb = new LiteDatabase("Filename=" + copy + ";Mode=Exclusive;Journal=true"))
                        read(ldb);
                    return;
                }
                catch (Exception ex) { last = ex; System.Threading.Thread.Sleep(1000 * attempt); }
                finally
                {
                    foreach (var f in new[] { copy, copyLog, copy + "-backup" })
                        try { if (File.Exists(f)) File.Delete(f); } catch { }
                }
            }
            throw new IOException("retail clients appear to be writing it; close your AC clients and try again (" + last?.Message + ")", last);
        }

        private static string Stamp(string path)
        {
            var fi = new FileInfo(path);
            return fi.Exists ? fi.Length + "@" + fi.LastWriteTimeUtc.Ticks + ";" : "-;";
        }

        private static void CopyShared(string from, string to)
        {
            using (var src = new FileStream(from, System.IO.FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var dst = File.Create(to))
                src.CopyTo(dst);
        }

        private static Dictionary<string, TValue> Bucket<TValue>(Dictionary<string, Dictionary<string, TValue>> d, string key)
        {
            key = key ?? "";
            if (!d.TryGetValue(key, out var inner)) d[key] = inner = new Dictionary<string, TValue>(StringComparer.OrdinalIgnoreCase);
            return inner;
        }

        private static string S(BsonDocument d, string field) => d.TryGetValue(field, out var v) && !v.IsNull ? (v.IsString ? v.AsString : v.ToString()) : "";

        /// <summary>
        /// Client library names allow 1-64 letters, digits, _ or -. Other characters become _,
        /// and if anything changed a 6-character hash of the original keeps names unique.
        /// </summary>
        public static string SafeName(string original, int maxLength)
        {
            var sb = new StringBuilder();
            foreach (var c in original ?? "")
                sb.Append((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' ? c : '_');
            var safe = sb.ToString();
            if (safe.Length > 0 && safe == original && safe.Length <= maxLength) return safe;
            string hash;
            using (var sha = SHA1.Create())
                hash = BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(original ?? ""))).Replace("-", "").Substring(0, 6).ToLowerInvariant();
            var keep = Math.Max(1, maxLength - 7);
            if (safe.Length > keep) safe = safe.Substring(0, keep);
            if (safe.Length == 0) safe = "x";
            return safe + "-" + hash;
        }
    }
}
