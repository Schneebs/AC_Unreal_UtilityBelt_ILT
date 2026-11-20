using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Threading.Tasks;

namespace UBManager
{
    internal sealed class ReleaseAsset
    {
        public string File, Url, Sha256, Version;
        public long Size;
    }

    internal sealed class ReleaseInfo
    {
        public string Version, Tag, Channel;
        public ReleaseAsset Plugin, Manager;
    }

    /// <summary>Reads latest.json published with each release (see tools/build-plugin.ps1).</summary>
    internal static class ReleaseFeed
    {
        public static async Task<ReleaseInfo> GetLatestAsync(string channel)
        {
            string latestUrl = Net.StableLatestUrl;
            if (channel == "beta")
            {
                // Newest release of any kind (GitHub lists newest first); pre-releases included.
                var list = Json.Parse(await Net.GetStringAsync(Net.ReleasesApiUrl).ConfigureAwait(false)) as object[];
                latestUrl = null;
                foreach (var item in list ?? new object[0])
                {
                    if (!(item is Dictionary<string, object> rel) || Equals(rel.GetValueOrDefault("draft"), true)) continue;
                    if (rel.GetValueOrDefault("assets") is object[] assets)
                        foreach (var a in assets)
                            if (a is Dictionary<string, object> asset && Json.Get(asset, "name") == "latest.json")
                            { latestUrl = Json.Get(asset, "browser_download_url"); break; }
                    if (latestUrl != null) break;
                }
                if (latestUrl == null) throw new InvalidDataException("No release with latest.json was found.");
                Net.RequireReleaseAssetUrl(latestUrl);
            }

            var o = Json.ParseObject(await Net.GetStringAsync(latestUrl).ConfigureAwait(false));
            var info = new ReleaseInfo
            {
                Version = Json.Get(o, "version"),
                Tag = Json.Get(o, "tag"),
                Channel = Json.Get(o, "channel"),
                Plugin = Asset(Json.GetObject(o, "plugin")),
                Manager = Asset(Json.GetObject(o, "manager")),
            };
            if (info.Plugin == null) throw new InvalidDataException("latest.json has no plugin entry.");
            return info;
        }

        private static ReleaseAsset Asset(Dictionary<string, object> o)
        {
            if (o == null) return null;
            var a = new ReleaseAsset
            {
                File = Json.Get(o, "file"),
                Url = Json.Get(o, "url"),
                Sha256 = Json.Get(o, "sha256"),
                Version = Json.Get(o, "version"),
            };
            long.TryParse(Json.Get(o, "size"), NumberStyles.Integer, CultureInfo.InvariantCulture, out a.Size);
            if (string.IsNullOrEmpty(a.Url) || string.IsNullOrEmpty(a.Sha256) || a.Sha256.Length != 64)
                throw new InvalidDataException("latest.json has an incomplete asset entry.");
            Net.RequireReleaseAssetUrl(a.Url);
            return a;
        }

        private static object GetValueOrDefault(this Dictionary<string, object> d, string key) =>
            d.TryGetValue(key, out var v) ? v : null;
    }
}
