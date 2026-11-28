// Wolf prices: the companion of Wolf (a World of Warcraft addon). One program:
//   started from a download:   setup (installs itself for you, no admin rights)
//   installed, at Windows start (--tray): the wolf by the clock, fetching new prices every 15 minutes
//   --uninstall:               removes itself (Settings > Apps > Uninstall runs this)
//   --check <World of Warcraft folder>, --pictures <folder>: for the build's own test (no window)
// What it touches: the addon's price file (Interface\AddOns\WolfOfBootyBay\Data\Feed.lua) and its note
// (Data\Companion.lua), its settings and log (%APPDATA%\WolfPrices), and itself. Source: github.com/PetcoWoW/ForeverTrading
using System;
using System.IO;
using System.Net;
using System.Windows.Forms;

namespace WolfPrices
{
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Func<string, bool> has = a => Array.IndexOf(args, a) >= 0;
            Func<string, string> arg = a => { int i = Array.IndexOf(args, a); return i >= 0 && i + 1 < args.Length ? args[i + 1] : null; };
            try
            {
                if (has("--check")) return Check(arg("--check"));
                if (has("--pictures")) return Pictures(arg("--pictures"), arg("--wow"));
                if (has("--uninstall")) { Installer.Uninstall(has("--quiet")); return 0; }
                // (1.1.1) setup without its window, for the build's own test (over a running copy)
                if (has("--install-quiet")) { Installer.Install(false); return 0; }
                if (has("--tray") || App.IsInstalledCopy) return Tray.Run(has("--updated"));
                return Setup.Run();
            }
            catch (Exception e)
            {
                Log.Write("stopped: " + e);
                if (!has("--check") && !has("--pictures") && !has("--tray") && !has("--install-quiet")) Ui.Tell("Something went wrong", e.Message);
                return 1;
            }
        }

        // one check against a World of Warcraft folder, the result in a file beside it (no window)
        static int Check(string root)
        {
            var f = Wow.In(root, null);
            var outFile = Path.Combine(root ?? ".", "wolfprices-check.txt");
            if (f == null) { File.WriteAllText(outFile, "addon not found\n"); return 2; }
            var r = Prices.Check(f);
            File.WriteAllText(outFile, string.Format("ok={0} downloaded={1} ready={2} inGame={3} error={4} version={5} wolfUpdated={6} wolfPending={7} wolfError={8}\n",
                r.Ok, r.Downloaded, r.Ready, r.InGame, r.Error, App.Version, r.Updated, r.Pending, AddonUpdate.Last.Error));
            return r.Ok ? 0 : 1;
        }

        // pictures of every page, for looking at the build
        static int Pictures(string dir, string root)
        {
            Directory.CreateDirectory(dir);
            var s = new Settings { WowRoot = root };
            var f = Wow.In(root, null);
            Action<WolfWindow, Page, string> save = (w, p, name) =>
            {
                w.SetPage(p);
                using (var bmp = w.Picture()) bmp.Save(Path.Combine(dir, name), System.Drawing.Imaging.ImageFormat.Png);
            };
            using (var w = new WolfWindow())
            {
                save(w, Setup.Welcome(w, s, f, x => { }), "1-setup.png");
                save(w, Setup.Welcome(w, new Settings(), null, x => { }), "2-setup-not-found.png");
                save(w, Setup.Done(w, true), "3-done.png");
                var q = new Page { Title = "Remove Wolf prices?", Body = "Your addon keeps working; prices then come only with addon updates.", Compact = true };
                q.Buttons.Add(new Button_ { Text = "Keep it" });
                q.Buttons.Add(new Button_ { Text = "Remove", Primary = true });
                save(w, q, "4-remove.png");
            }
            return 0;
        }
    }
}
