// Wolf prices: where things live, the log and the settings.
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

namespace WolfPrices
{
    static class App
    {
        public const string Repo = "PetcoWoW/ForeverTrading";
        public const string InfoUrl = "https://github.com/" + Repo + "/releases/latest/download/latest.json";
        public const string FeedUrl = "https://github.com/" + Repo + "/releases/latest/download/Feed.lua";
        // the companion itself, for its own updates: a release of its own (tag "companion")
        public const string SelfInfoUrl = "https://github.com/" + Repo + "/releases/download/companion/companion.json";
        public const string SelfExeUrl = "https://github.com/" + Repo + "/releases/download/companion/WolfPrices.exe";
        public const int EveryMinutes = 15;
        public const string Name = "Wolf prices";

        public static string Version
        {
            get
            {
                var a = typeof(App).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>();
                return a != null ? a.InformationalVersion : "0.0.0";
            }
        }

        // settings and the log (the same folder the first companion used)
        public static string DataDir
        {
            get
            {
                var d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WolfPrices");
                Directory.CreateDirectory(d);
                return d;
            }
        }

        // the program: installed for this Windows user only, no admin rights
        public static string InstallDir
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "WolfPrices"); }
        }
        public static string InstalledExe { get { return Path.Combine(InstallDir, "WolfPrices.exe"); } }
        public static string SelfExe { get { return Path.GetFullPath(System.Windows.Forms.Application.ExecutablePath); } }
        public static bool IsInstalledCopy
        {
            get { return string.Equals(SelfExe, Path.GetFullPath(InstalledExe), StringComparison.OrdinalIgnoreCase); }
        }
    }

    static class Log
    {
        static readonly object gate = new object();
        public static void Write(string msg)
        {
            try
            {
                lock (gate)
                {
                    var file = Path.Combine(App.DataDir, "log.txt");
                    File.AppendAllText(file, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + msg + Environment.NewLine, Encoding.UTF8);
                    var info = new FileInfo(file);
                    if (info.Length > 200 * 1024)
                    {
                        var lines = File.ReadAllLines(file, Encoding.UTF8);
                        var keep = new List<string>();
                        for (int i = Math.Max(0, lines.Length - 800); i < lines.Length; i++) keep.Add(lines[i]);
                        File.WriteAllLines(file, keep, Encoding.UTF8);
                    }
                }
            }
            catch { }
        }
    }

    // a few key=value lines in %APPDATA%\WolfPrices\settings.txt
    class Settings
    {
        public string WowRoot;
        public string Flavor;
        public bool AutoUpdate = true;   // (1.1) keep Wolf itself up to date
        public string Updated;           // the last Wolf it put in, and when
        public long UpdatedAt;

        static string File_ { get { return Path.Combine(App.DataDir, "settings.txt"); } }

        public static Settings Load()
        {
            var s = new Settings();
            try
            {
                if (File.Exists(File_))
                {
                    foreach (var line in File.ReadAllLines(File_, Encoding.UTF8))
                    {
                        int eq = line.IndexOf('=');
                        if (eq <= 0) continue;
                        var k = line.Substring(0, eq).Trim();
                        var v = line.Substring(eq + 1).Trim();
                        if (k == "wowRoot") s.WowRoot = v;
                        else if (k == "flavor") s.Flavor = v;
                        else if (k == "autoUpdate") s.AutoUpdate = v != "0";
                        else if (k == "updated") s.Updated = v;
                        else if (k == "updatedAt") { long n; if (long.TryParse(v, out n)) s.UpdatedAt = n; }
                    }
                }
                else
                {
                    // the first companion's settings
                    var old = Path.Combine(App.DataDir, "config.json");
                    if (File.Exists(old))
                    {
                        var text = File.ReadAllText(old, Encoding.UTF8);
                        var m = Regex.Match(text, "\"wowRoot\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
                        if (m.Success) s.WowRoot = Regex.Unescape(m.Groups[1].Value);
                        m = Regex.Match(text, "\"flavor\"\\s*:\\s*\"([^\"]*)\"");
                        if (m.Success) s.Flavor = m.Groups[1].Value;
                    }
                }
            }
            catch (Exception e) { Log.Write("settings unreadable: " + e.Message); }
            return s;
        }

        public void Save()
        {
            try
            {
                File.WriteAllLines(File_, new[] { "wowRoot=" + (WowRoot ?? ""), "flavor=" + (Flavor ?? ""), "autoUpdate=" + (AutoUpdate ? "1" : "0"),
                    "updated=" + (Updated ?? ""), "updatedAt=" + UpdatedAt }, Encoding.UTF8);
            }
            catch (Exception e) { Log.Write("settings not saved: " + e.Message); }
        }
    }

    static class Fmt
    {
        public static DateTime Local(long unix) { return DateTimeOffset.FromUnixTimeSeconds(unix).LocalDateTime; }
        public static long Now() { return DateTimeOffset.UtcNow.ToUnixTimeSeconds(); }

        // "3:05 pm", or "Tue 3:05 pm" when not today
        public static string Time(long unix)
        {
            if (unix <= 0) return "?";
            var dt = Local(unix);
            var inv = System.Globalization.CultureInfo.InvariantCulture;
            var s = dt.ToString("h:mm tt", inv).ToLowerInvariant();
            if (dt.Date != DateTime.Now.Date) s = dt.ToString("ddd", inv) + " " + s;
            return s;
        }
    }
}
