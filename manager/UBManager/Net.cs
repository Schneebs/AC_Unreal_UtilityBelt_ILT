using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Threading.Tasks;

namespace UBManager
{
    /// <summary>HTTPS downloads restricted to this project's GitHub releases.</summary>
    internal static class Net
    {
        public const string Repo = "Schneebs/AC_Unreal_UtilityBelt_ILT";
        public const string StableLatestUrl = "https://github.com/" + Repo + "/releases/latest/download/latest.json";
        public const string ReleasesApiUrl = "https://api.github.com/repos/" + Repo + "/releases?per_page=20";
        private const string ReleaseDownloadPrefix = "https://github.com/" + Repo + "/releases/download/";

        // Hosts GitHub serves release files from (after redirects).
        private static readonly string[] AllowedHosts =
            { "github.com", "api.github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com" };

        private static readonly HttpClient Client = CreateClient();

        public static void EnableModernTls()
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
        }

        private static HttpClient CreateClient()
        {
            var handler = new HttpClientHandler { AllowAutoRedirect = true };
            var client = new HttpClient(handler) { Timeout = TimeSpan.FromMinutes(5) };
            client.DefaultRequestHeaders.UserAgent.ParseAdd("UBManager/" + Program.Version);
            client.DefaultRequestHeaders.Accept.ParseAdd("application/json");
            return client;
        }

        /// <summary>Only release assets of this repository may be downloaded.</summary>
        public static void RequireReleaseAssetUrl(string url)
        {
            if (string.IsNullOrEmpty(url) || !url.StartsWith(ReleaseDownloadPrefix, StringComparison.Ordinal))
                throw new InvalidDataException("Refusing to download from an unexpected address: " + url);
        }

        private static void CheckFinalHost(HttpResponseMessage response)
        {
            var uri = response.RequestMessage?.RequestUri;
            if (uri == null || uri.Scheme != Uri.UriSchemeHttps || Array.IndexOf(AllowedHosts, uri.Host.ToLowerInvariant()) < 0)
                throw new InvalidDataException("Download was redirected to an unexpected host: " + uri);
        }

        public static async Task<string> GetStringAsync(string url)
        {
            using (var response = await Client.GetAsync(url).ConfigureAwait(false))
            {
                CheckFinalHost(response);
                response.EnsureSuccessStatusCode();
                return await response.Content.ReadAsStringAsync().ConfigureAwait(false);
            }
        }

        /// <summary>Downloads to a file and checks size and SHA-256; deletes the file on any mismatch.</summary>
        public static async Task DownloadVerifiedAsync(string url, string destination, string expectedSha256, long expectedSize)
        {
            RequireReleaseAssetUrl(url);
            Directory.CreateDirectory(Path.GetDirectoryName(destination));
            try
            {
                using (var response = await Client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false))
                {
                    CheckFinalHost(response);
                    response.EnsureSuccessStatusCode();
                    using (var input = await response.Content.ReadAsStreamAsync().ConfigureAwait(false))
                    using (var output = File.Create(destination))
                        await input.CopyToAsync(output).ConfigureAwait(false);
                }
                var size = new FileInfo(destination).Length;
                if (expectedSize > 0 && size != expectedSize)
                    throw new InvalidDataException($"Downloaded size {size} does not match the expected {expectedSize} bytes.");
                var actual = Sha256(destination);
                if (!string.Equals(actual, expectedSha256, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("Checksum mismatch: the download is corrupt or was tampered with.");
            }
            catch
            {
                try { File.Delete(destination); } catch { /* best effort */ }
                throw;
            }
        }

        public static string Sha256(string path)
        {
            using (var sha = SHA256.Create())
            using (var stream = File.OpenRead(path))
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
        }
    }
}
