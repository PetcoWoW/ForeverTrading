// Wolf prices: keeping Wolf itself up to date (companion 1.1). The price robot's note (latest.json) names the commit
// the newest Wolf is built from, its zip and the zip's fingerprint. When that's another commit than the one in the
// addon folder (its TOC's "## X-Commit"), the zip is downloaded, checked against its fingerprint and unpacked, and
// the files are swapped in - while you play: a /reload loads new code (the same reload that loads new prices).
// The game reads the TOC only at launch, though, so a Wolf whose TOC changed (a new file) waits until the game is
// closed: a reload would run new code without its new files. Kept as they are: the prices (whichever are newer) and
// the companion's note. Never touched: a copy made with git (a developer's), or when "Keep Wolf updated" is off.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace WolfPrices
{
    class UpdateState
    {
        public string Updated;   // the version this check put in
        public long UpdatedAt;
        public string Pending;   // a newer one waiting for the game to close
        public string Error;
    }

    static class AddonUpdate
    {
        static UpdateState last = new UpdateState();
        public static UpdateState Last { get { return last; } }

        static string Toc(Found f) { return Path.Combine(f.Addon, "WolfOfBootyBay.toc"); }

        public static string TocField(string tocFile, string key)
        {
            if (!File.Exists(tocFile)) return null;
            foreach (var line in File.ReadAllLines(tocFile, Encoding.UTF8))
            {
                var t = line.Trim();
                if (t.StartsWith("## " + key + ":", StringComparison.OrdinalIgnoreCase)) return t.Substring(key.Length + 4).Trim();
            }
            return null;
        }

        // what the game reads from a TOC at launch: every line but the version and the commit
        public static string TocShape(string tocFile)
        {
            var keep = new List<string>();
            foreach (var line in File.ReadAllLines(tocFile, Encoding.UTF8))
            {
                var t = line.Trim().Replace('/', '\\');
                if (t.Length == 0 || t.StartsWith("## Version:", StringComparison.OrdinalIgnoreCase) || t.StartsWith("## X-Commit:", StringComparison.OrdinalIgnoreCase)) continue;
                keep.Add(t.ToLowerInvariant());
            }
            return string.Join("\n", keep);
        }

        public static bool GameRunning()
        {
            try
            {
                return Process.GetProcesses().Any(p =>
                {
                    try { return p.ProcessName.StartsWith("Wow", StringComparison.OrdinalIgnoreCase); }
                    catch { return false; }
                });
            }
            catch { return false; }
        }

        static string Sha256(string file)
        {
            using (var s = File.OpenRead(file))
            using (var h = SHA256.Create())
                return BitConverter.ToString(h.ComputeHash(s)).Replace("-", "").ToLowerInvariant();
        }

        // one look, after the price check (info: the robot's latest.json)
        public static UpdateState Run(Found f, string info, Settings s, bool gameRunning)
        {
            last.Updated = null;
            last.Pending = null;
            last.Error = null;
            try
            {
                if (!s.AutoUpdate) return last;
                if (Directory.Exists(Path.Combine(f.Addon, ".git"))) return last; // a developer's copy
                var commit = Prices.JsonString(info, "addonCommit");
                var zipUrl = Prices.JsonString(info, "addonZip");
                var sha = (Prices.JsonString(info, "addonSha256") ?? "").ToLowerInvariant();
                var version = Prices.JsonString(info, "addonVersion");
                if (string.IsNullOrEmpty(commit) || string.IsNullOrEmpty(zipUrl) || sha.Length != 64 || string.IsNullOrEmpty(version)) return last;
                var have = TocField(Toc(f), "X-Commit");
                if (string.Equals(have, commit, StringComparison.OrdinalIgnoreCase)) return last;

                var work = Path.Combine(Path.GetTempPath(), "WolfPrices-update");
                if (Directory.Exists(work)) Directory.Delete(work, true);
                Directory.CreateDirectory(work);
                var zip = Path.Combine(work, "wolf.zip");
                Prices.Download(zipUrl, zip, 180);
                if (Sha256(zip) != sha) throw new Exception("the download didn't match its fingerprint (kept the one there)");
                var unpacked = Path.Combine(work, "x");
                ZipFile.ExtractToDirectory(zip, unpacked);
                var src = Path.Combine(unpacked, "WolfOfBootyBay");
                var newToc = Path.Combine(src, "WolfOfBootyBay.toc");
                if (!File.Exists(newToc) || !File.Exists(Path.Combine(src, "Core.lua")) || !string.Equals(TocField(newToc, "X-Commit"), commit, StringComparison.OrdinalIgnoreCase))
                    throw new Exception("the download didn't look like Wolf (kept the one there)");

                // a changed TOC (a new file) only loads at the game's launch: wait for it to be closed
                if (gameRunning && File.Exists(Toc(f)) && TocShape(Toc(f)) != TocShape(newToc))
                {
                    last.Pending = version;
                    Log.Write("Wolf " + version + " waits for the game to close (it has new files)");
                    return last;
                }

                Swap(f, src);
                last.Updated = version;
                last.UpdatedAt = Fmt.Now();
                Log.Write("updated Wolf to " + version + (gameRunning ? " (a /reload loads it)" : ""));
                try { Directory.Delete(work, true); } catch { }
            }
            catch (Exception e)
            {
                last.Error = e.Message;
                Log.Write("Wolf update: " + e.Message);
            }
            return last;
        }

        // the new files over the old ones, each swapped whole; the TOC last
        static void Swap(Found f, string src)
        {
            var skip = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { Path.Combine("Data", "Companion.lua"), "WolfOfBootyBay.toc" };
            var feedRel = Path.Combine("Data", "Feed.lua");
            // the prices: whichever are newer stay
            var diskFeed = Prices.Times(f.FeedFile);
            var zipFeed = Prices.Times(Path.Combine(src, feedRel));
            if (zipFeed.Built <= diskFeed.Built) skip.Add(feedRel);
            foreach (var file in Directory.GetFiles(src, "*", SearchOption.AllDirectories))
            {
                var rel = file.Substring(src.Length).TrimStart('\\', '/');
                if (skip.Contains(rel)) continue;
                Put(file, Path.Combine(f.Addon, rel));
            }
            Put(Path.Combine(src, "WolfOfBootyBay.toc"), Toc(f));
        }

        static void Put(string from, string to)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(to));
            var tmp = to + ".new";
            File.Copy(from, tmp, true);
            if (File.Exists(to)) File.Replace(tmp, to, null);
            else File.Move(tmp, to);
        }
    }
}
