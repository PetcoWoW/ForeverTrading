// Wolf prices: where the addon is. World of Warcraft's folder from the Battle.net install (the registry), the usual
// places, or the folder you picked; then the game version's folder (_forever_ first) that has the addon in it.
using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Win32;

namespace WolfPrices
{
    class Found
    {
        public string Root;    // ...\World of Warcraft
        public string Flavor;  // _forever_
        public string Dir;     // ...\World of Warcraft\_forever_
        public string Addon;   // ...\_forever_\Interface\AddOns\WolfOfBootyBay
        public string FeedFile { get { return Path.Combine(Addon, "Data", "Feed.lua"); } }
        public string NoteFile { get { return Path.Combine(Addon, "Data", "Companion.lua"); } }
    }

    static class Wow
    {
        static readonly string[] Flavors = { "_forever_", "_classic_beta_", "_classic_era_", "_classic_", "_retail_" };

        public static List<string> Roots()
        {
            var roots = new List<string>();
            foreach (var key in new[] { @"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
                                        @"SOFTWARE\Blizzard Entertainment\World of Warcraft" })
            {
                try
                {
                    using (var k = Registry.LocalMachine.OpenSubKey(key))
                    {
                        var p = k == null ? null : k.GetValue("InstallPath") as string;
                        if (!string.IsNullOrEmpty(p))
                        {
                            p = p.TrimEnd('\\');
                            // InstallPath is one game version's folder (...\World of Warcraft\_retail_): its parent
                            var leaf = Path.GetFileName(p);
                            if (leaf.StartsWith("_") && leaf.EndsWith("_")) p = Path.GetDirectoryName(p);
                            if (!roots.Contains(p)) roots.Add(p);
                        }
                    }
                }
                catch { }
            }
            var pf86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            var pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            foreach (var p in new[] { Path.Combine(pf86, "World of Warcraft"), Path.Combine(pf, "World of Warcraft"),
                                      @"C:\World of Warcraft", @"D:\World of Warcraft", @"D:\Games\World of Warcraft",
                                      @"E:\World of Warcraft", @"C:\Games\World of Warcraft", @"E:\Games\World of Warcraft" })
            {
                if (!roots.Contains(p)) roots.Add(p);
            }
            return roots;
        }

        public static Found In(string root, string prefer)
        {
            if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) return null;
            var order = new List<string>();
            if (!string.IsNullOrEmpty(prefer)) order.Add(prefer);
            foreach (var f in Flavors) if (!order.Contains(f)) order.Add(f);
            foreach (var f in order)
            {
                var dir = Path.Combine(root, f);
                var addon = Path.Combine(dir, "Interface", "AddOns", "WolfOfBootyBay");
                if (File.Exists(Path.Combine(addon, "WolfOfBootyBay.toc")))
                    return new Found { Root = root, Flavor = f, Dir = dir, Addon = addon };
            }
            return null;
        }

        // the game's folder of a game version, without the addon (to say "the addon isn't in there yet")
        public static string GameIn(string root)
        {
            if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) return null;
            foreach (var f in Flavors)
            {
                var dir = Path.Combine(root, f);
                if (Directory.Exists(dir)) return dir;
            }
            return null;
        }

        // a folder someone picked: World of Warcraft, a game version's folder, AddOns or the addon itself - walk up
        public static Found FromPicked(string picked)
        {
            var p = picked;
            for (int i = 0; i < 5 && !string.IsNullOrEmpty(p); i++)
            {
                var f = In(p, null);
                if (f != null) return f;
                p = Path.GetDirectoryName(p);
            }
            return null;
        }

        public static Found Resolve(Settings s)
        {
            var found = In(s.WowRoot, s.Flavor);
            if (found == null)
            {
                foreach (var r in Roots())
                {
                    found = In(r, null);
                    if (found != null) break;
                }
            }
            if (found != null && (found.Root != s.WowRoot || found.Flavor != s.Flavor))
            {
                s.WowRoot = found.Root;
                s.Flavor = found.Flavor;
                s.Save();
            }
            return found;
        }

        // World of Warcraft's folder, found or not (for the setup window)
        public static string AnyRoot(Settings s)
        {
            if (!string.IsNullOrEmpty(s.WowRoot) && Directory.Exists(s.WowRoot)) return s.WowRoot;
            foreach (var r in Roots()) if (GameIn(r) != null) return r;
            return null;
        }
    }
}
