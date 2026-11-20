using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace UBManager
{
    /// <summary>Small JSON helpers over JavaScriptSerializer (built into .NET Framework).</summary>
    internal static class Json
    {
        private static JavaScriptSerializer Serializer() => new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 256 };

        public static object Parse(string text) => Serializer().DeserializeObject(text);

        public static Dictionary<string, object> ParseObject(string text) =>
            Parse(text) as Dictionary<string, object> ?? throw new InvalidDataException("Expected a JSON object.");

        public static Dictionary<string, object> ReadObjectFile(string path) => ParseObject(File.ReadAllText(path, Encoding.UTF8));

        public static string Get(Dictionary<string, object> o, string key) =>
            o != null && o.TryGetValue(key, out var v) && v != null ? Convert.ToString(v, CultureInfo.InvariantCulture) : null;

        public static Dictionary<string, object> GetObject(Dictionary<string, object> o, string key) =>
            o != null && o.TryGetValue(key, out var v) ? v as Dictionary<string, object> : null;

        /// <summary>Indented, UTF-8 (no BOM), LF line endings.</summary>
        public static void WriteFile(string path, object value)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, Stringify(value), new UTF8Encoding(false));
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }

        public static string Stringify(object value)
        {
            var sb = new StringBuilder();
            Write(sb, value, 0);
            sb.Append('\n');
            return sb.ToString();
        }

        private static void Write(StringBuilder sb, object v, int depth)
        {
            switch (v)
            {
                case null: sb.Append("null"); return;
                case string s: WriteString(sb, s); return;
                case bool b: sb.Append(b ? "true" : "false"); return;
                case DateTime dt: WriteString(sb, dt.ToUniversalTime().ToString("o", CultureInfo.InvariantCulture)); return;
                case IDictionary dict:
                    if (dict.Count == 0) { sb.Append("{}"); return; }
                    sb.Append("{\n");
                    var first = true;
                    foreach (DictionaryEntry e in dict)
                    {
                        if (!first) sb.Append(",\n");
                        first = false;
                        sb.Append(' ', (depth + 1) * 2);
                        WriteString(sb, Convert.ToString(e.Key, CultureInfo.InvariantCulture));
                        sb.Append(": ");
                        Write(sb, e.Value, depth + 1);
                    }
                    sb.Append('\n').Append(' ', depth * 2).Append('}');
                    return;
                case IEnumerable list:
                    var items = new List<object>();
                    foreach (var x in list) items.Add(x);
                    if (items.Count == 0) { sb.Append("[]"); return; }
                    sb.Append("[\n");
                    for (var i = 0; i < items.Count; i++)
                    {
                        if (i > 0) sb.Append(",\n");
                        sb.Append(' ', (depth + 1) * 2);
                        Write(sb, items[i], depth + 1);
                    }
                    sb.Append('\n').Append(' ', depth * 2).Append(']');
                    return;
                case IFormattable f when IsNumber(v):
                    var n = f.ToString(null, CultureInfo.InvariantCulture);
                    sb.Append(n == "NaN" || n.Contains("Infinity") ? "null" : n);
                    return;
                default: WriteString(sb, Convert.ToString(v, CultureInfo.InvariantCulture)); return;
            }
        }

        private static bool IsNumber(object v) =>
            v is int || v is long || v is double || v is float || v is decimal || v is short || v is byte || v is uint || v is ulong;

        private static void WriteString(StringBuilder sb, string s)
        {
            sb.Append('"');
            foreach (var c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }
    }
}
