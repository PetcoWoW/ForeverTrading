// Wolf prices: one check. Asks the price robot (GitHub) when its newest prices are from - a note of a few hundred
// bytes - and when they're newer than the ones in the addon folder, downloads the price file and swaps it in. Then
// leaves the addon a note (Data\Companion.lua) of when it checked: the addon reads it at login and /reload, and from
// it knows newer prices are waiting (it says so in chat, at the auction house). Never a pop-up or a sound.
using System;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace WolfPrices
{
    class CheckResult
    {
        public bool Ok;
        public bool Downloaded;
        public long Ready;   // Blizzard's time of the prices on disk
        public long InGame;  // ...of the prices the game loaded last
        public string Error;
    }

    static class Prices
    {
        public class FeedTimes { public long T; public long Built; }

        // the newest house time in a price file (its lines "[110] = { t = 1795562778, ..."), and when it was built
        public static FeedTimes Times(string file)
        {
            var r = new FeedTimes();
            if (!File.Exists(file)) return r;
            var houseT = new Regex(@"\[\d+\] = \{ t = (\d+),");
            var built = new Regex(@"built = (\d+)");
            int n = 0;
            using (var rd = new StreamReader(file, Encoding.UTF8))
            {
                string line;
                while ((line = rd.ReadLine()) != null)
                {
                    n++;
                    if (n <= 8 && r.Built == 0)
                    {
                        var b = built.Match(line);
                        if (b.Success) r.Built = long.Parse(b.Groups[1].Value);
                    }
                    if (line.IndexOf("{ t = ", StringComparison.Ordinal) < 0) continue;
                    foreach (Match m in houseT.Matches(line))
                    {
                        long v = long.Parse(m.Groups[1].Value);
                        if (v > r.T) r.T = v;
                    }
                }
            }
            return r;
        }

        // which prices the game loaded last: the addon keeps them in its saved data, written at every /reload and
        // logout (the newest file of every account); 0 when not seen yet
        public static long InGame(Found f)
        {
            long best = 0;
            try
            {
                var accounts = Path.Combine(f.Dir, "WTF", "Account");
                if (!Directory.Exists(accounts)) return 0;
                FileInfo newest = null;
                foreach (var acc in Directory.GetDirectories(accounts))
                {
                    var sv = new FileInfo(Path.Combine(acc, "SavedVariables", "WolfOfBootyBay.lua"));
                    if (sv.Exists && (newest == null || sv.LastWriteTimeUtc > newest.LastWriteTimeUtc)) newest = sv;
                }
                if (newest == null) return 0;
                var text = File.ReadAllText(newest.FullName, Encoding.UTF8);
                var m = Regex.Match(text, @"\[""feedLoaded""\]\s*=\s*\{([^}]*)\}", RegexOptions.Singleline);
                if (m.Success)
                {
                    foreach (Match v in Regex.Matches(m.Groups[1].Value, @"=\s*(\d+)"))
                    {
                        long x = long.Parse(v.Groups[1].Value);
                        if (x > best) best = x;
                    }
                }
            }
            catch { }
            return best;
        }

        public static string Get(string url, int timeoutSec)
        {
            var req = (HttpWebRequest)WebRequest.Create(url);
            req.Timeout = timeoutSec * 1000;
            req.ReadWriteTimeout = timeoutSec * 1000;
            req.UserAgent = "WolfPrices/" + App.Version;
            req.Headers.Add("Cache-Control", "no-cache");
            req.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
            using (var resp = (HttpWebResponse)req.GetResponse())
            using (var s = resp.GetResponseStream())
            using (var rd = new StreamReader(s, Encoding.UTF8))
                return rd.ReadToEnd();
        }

        public static void Download(string url, string file, int timeoutSec)
        {
            var req = (HttpWebRequest)WebRequest.Create(url);
            req.Timeout = timeoutSec * 1000;
            req.ReadWriteTimeout = timeoutSec * 1000;
            req.UserAgent = "WolfPrices/" + App.Version;
            req.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
            using (var resp = (HttpWebResponse)req.GetResponse())
            using (var s = resp.GetResponseStream())
            using (var o = File.Create(file))
                s.CopyTo(o);
        }

        public static long JsonNumber(string json, string key)
        {
            var m = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*(\\d+)");
            return m.Success ? long.Parse(m.Groups[1].Value) : 0;
        }
        public static string JsonString(string json, string key)
        {
            var m = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"([^\"]*)\"");
            return m.Success ? m.Groups[1].Value : null;
        }

        public static CheckResult Check(Found f)
        {
            var res = new CheckResult();
            var feed = f.FeedFile;
            try
            {
                var info = Get(App.InfoUrl, 30);
                long builtNow = JsonNumber(info, "built");
                if (builtNow <= 0) throw new Exception("the price note had no time in it");
                var disk = Times(feed);
                if (builtNow > disk.Built)
                {
                    var tmp = feed + ".download";
                    Download(App.FeedUrl, tmp, 180);
                    // only a whole, real price file replaces the one there
                    string first;
                    using (var rd = new StreamReader(tmp, Encoding.UTF8)) first = rd.ReadLine() ?? "";
                    var got = Times(tmp);
                    if (new FileInfo(tmp).Length < 10000 || !first.StartsWith("-- Generated by tools/feed/build.mjs") || got.Built < builtNow)
                    {
                        try { File.Delete(tmp); } catch { }
                        throw new Exception("the downloaded price file didn't look right (kept the old one)");
                    }
                    if (File.Exists(feed)) File.Replace(tmp, feed, null);
                    else File.Move(tmp, feed);
                    res.Downloaded = true;
                    Log.Write("new prices: Blizzard " + Fmt.Time(got.T) + ", built " + Fmt.Time(got.Built));
                    disk = got;
                }
                res.Ready = disk.T;
                res.Ok = true;
                WriteNote(f, disk);
            }
            catch (Exception e)
            {
                res.Error = e.Message;
                try { res.Ready = Times(feed).T; } catch { }
                Log.Write("check failed: " + e.Message);
            }
            res.InGame = InGame(f);
            return res;
        }

        // the note for the addon (Data\Companion.lua, in its TOC): read by the game at login and /reload
        public static void WriteNote(Found f, FeedTimes disk)
        {
            var sb = new StringBuilder();
            sb.Append("-- Written by the Wolf prices companion (Windows) every time it checks for new prices: when it last checked, which\n");
            sb.Append("-- prices it put in Data\\Feed.lua, its version. Empty in a fresh copy of the addon: the companion fills it in.\n");
            sb.Append("local ADDON, FT = ...\n");
            sb.AppendFormat("FT.COMPANION = {{ version = \"{0}\", checked = {1}, built = {2}, t = {3} }}\n",
                App.Version, Fmt.Now(), disk.Built, disk.T);
            WriteNoteText(f, sb.ToString());
        }

        // back to how a fresh copy of the addon has it (uninstalling)
        public static void ClearNote(Found f)
        {
            WriteNoteText(f,
                "-- Written by the Wolf prices companion (Windows) every time it checks for new prices: when it last checked, which\n" +
                "-- prices it put in Data\\Feed.lua, its version. Empty in a fresh copy of the addon: the companion fills it in.\n" +
                "local ADDON, FT = ...\nFT.COMPANION = FT.COMPANION or nil\n");
        }

        static void WriteNoteText(Found f, string text)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(f.NoteFile));
                var tmp = f.NoteFile + ".tmp";
                File.WriteAllText(tmp, text, new UTF8Encoding(false));
                if (File.Exists(f.NoteFile)) File.Replace(tmp, f.NoteFile, null);
                else File.Move(tmp, f.NoteFile);
            }
            catch (Exception e) { Log.Write("note not written: " + e.Message); }
        }
    }
}
