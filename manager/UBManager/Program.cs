using System;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

namespace UBManager
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            // LiteDB and its dependency ship inside the exe so players get a single file.
            AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
            {
                var simpleName = new AssemblyName(e.Name).Name;
                if (simpleName != "LiteDB") return null;
                using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(simpleName + ".dll"))
                {
                    if (stream == null) return null;
                    var bytes = new byte[stream.Length];
                    var read = 0;
                    while (read < bytes.Length) read += stream.Read(bytes, read, bytes.Length - read);
                    return Assembly.Load(bytes);
                }
            };

            Net.EnableModernTls();
            SelfUpdater.CleanUpAfterUpdate();

            if (args.Length > 0 && args[0].StartsWith("--", StringComparison.Ordinal))
                return Cli.Run(args);

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
            return 0;
        }

        public static string Version
        {
            get
            {
                var info = Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>();
                var v = info?.InformationalVersion ?? "0.0.0-dev";
                var plus = v.IndexOf('+');            // drop SDK source-revision suffix
                return plus >= 0 ? v.Substring(0, plus) : v;
            }
        }

        public static string DataDirectory
        {
            get
            {
                var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "UBManager");
                Directory.CreateDirectory(dir);
                return dir;
            }
        }
    }
}
