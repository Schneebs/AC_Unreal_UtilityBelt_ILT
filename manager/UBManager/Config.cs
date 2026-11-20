using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace UBManager
{
    /// <summary>UB Manager's own settings: %LOCALAPPDATA%\UBManager\config.json.</summary>
    internal sealed class Config
    {
        public string Channel = "stable";              // "stable" or "beta"
        public List<string> ExtraClientFolders = new List<string>();
        public string SelectedClient;
        public string RetailFolder;

        private static string PathOf => Path.Combine(Program.DataDirectory, "config.json");

        public static Config Load()
        {
            var c = new Config();
            try
            {
                if (!File.Exists(PathOf)) return c;
                var o = Json.ReadObjectFile(PathOf);
                c.Channel = Json.Get(o, "channel") == "beta" ? "beta" : "stable";
                c.SelectedClient = Json.Get(o, "selected_client");
                c.RetailFolder = Json.Get(o, "retail_folder");
                if (o.TryGetValue("extra_client_folders", out var list) && list is object[] arr)
                    c.ExtraClientFolders = arr.Select(x => Convert.ToString(x)).Where(s => !string.IsNullOrEmpty(s)).ToList();
            }
            catch { /* a broken config falls back to defaults */ }
            return c;
        }

        public void Save()
        {
            Json.WriteFile(PathOf, new Dictionary<string, object>
            {
                ["channel"] = Channel,
                ["selected_client"] = SelectedClient,
                ["retail_folder"] = RetailFolder,
                ["extra_client_folders"] = ExtraClientFolders,
            });
        }
    }
}
