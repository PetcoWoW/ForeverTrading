// Wolf prices: setup. One window: what it does in a line, ticks for World of Warcraft and the addon, "Start with
// Windows" already ticked, Install. Then a last page: done, where the wolf is, and that chat says when to /reload.
// Started again once it's installed (the Start menu): a small status window instead.
using System;
using System.Windows.Forms;

namespace WolfPrices
{
    static class Setup
    {
        const string Pitch = "Keeps your auction house prices fresh. Every 15 minutes it quietly brings Blizzard's newest prices into your addon: no pop-ups, no sounds, nothing on stream. In game, chat says when there are newer ones to load.";
        const string Small = "Installs for you only, no admin rights. Remove it any time: Settings > Apps.";

        public static Page Welcome(WolfWindow w, Settings s, Found found, Action<Found> retry)
        {
            var p = new Page
            {
                Title = App.Name,
                Subtitle = "the companion of The Wolf of Booty Bay",
                Body = Pitch,
                CheckText = "Start with Windows",
                Checked = true,
                Footer = Small,
            };
            Action pick = () =>
            {
                using (var dlg = new FolderBrowserDialog())
                {
                    dlg.Description = "Where is World of Warcraft? Pick the \"World of Warcraft\" folder (the one with _forever_ in it).";
                    dlg.ShowNewFolderButton = false;
                    if (dlg.ShowDialog(w) == DialogResult.OK)
                    {
                        var f = Wow.FromPicked(dlg.SelectedPath);
                        if (f != null) { s.WowRoot = f.Root; s.Flavor = f.Flavor; s.Save(); }
                        retry(f);
                    }
                }
            };
            var root = found != null ? found.Root : Wow.AnyRoot(s);
            if (root != null)
                p.Rows.Add(new Row { Ok = true, Label = "World of Warcraft", Detail = found != null ? found.Dir : root,
                    Link = found == null ? null : new Button_ { Text = "Change", Click = pick } });
            else
                p.Rows.Add(new Row { Ok = false, Label = "World of Warcraft", Detail = "not found", Link = new Button_ { Text = "Pick folder...", Click = pick } });
            if (found != null)
                p.Rows.Add(new Row { Ok = true, Label = "The Wolf of Booty Bay", Detail = "installed" });
            else
                p.Rows.Add(new Row { Ok = false, Label = "The Wolf of Booty Bay", Detail = "get it from CurseForge first",
                    Link = new Button_ { Text = "Look again", Click = () => retry(Wow.Resolve(s)) } });
            p.Buttons.Add(new Button_ { Text = "Cancel", Click = () => w.Close() });
            p.Buttons.Add(new Button_ { Text = Installer.IsInstalled ? "Update" : "Install", Primary = true, Enabled = found != null });
            return p;
        }

        public static Page Done(WolfWindow w, bool startup)
        {
            var p = new Page
            {
                Title = "All set",
                Subtitle = "the wolf is by your clock",
                Body = "Your prices stay fresh from now on" + (startup ? ", every time Windows starts." : " (start it from the Start menu after a restart).") +
                       " When you open the auction house and newer prices are waiting, chat says so: click Load them, done.\n\n" +
                       "Hover the wolf by the clock to see when your prices are from. Windows may tuck it under the ^ arrow.",
            };
            p.Buttons.Add(new Button_ { Text = "Finish", Primary = true, Click = () => w.Close() });
            return p;
        }

        public static int Run()
        {
            var s = Settings.Load();
            using (var w = new WolfWindow())
            {
                bool installed = false, startup = true;
                Action<Found> show = null;
                show = f =>
                {
                    var page = Welcome(w, s, f, show);
                    var install = page.Buttons[page.Buttons.Count - 1];
                    install.Click = () =>
                    {
                        if (f == null) return;
                        try
                        {
                            startup = w.CheckValue;
                            w.Cursor = Cursors.WaitCursor;
                            s.WowRoot = f.Root; s.Flavor = f.Flavor; s.Save();
                            Installer.Install(startup);
                            installed = true;
                            w.Cursor = Cursors.Default;
                            w.SetPage(Done(w, startup));
                        }
                        catch (Exception e)
                        {
                            w.Cursor = Cursors.Default;
                            Log.Write("install failed: " + e);
                            Ui.Tell("Couldn't install", e.Message);
                        }
                    };
                    w.SetPage(page);
                };
                show(Wow.Resolve(s));
                Application.Run(w);
                if (installed)
                {
                    try { Installer.Launch(); } catch (Exception e) { Log.Write("start after install: " + e.Message); }
                }
            }
            return 0;
        }

        // started from the Start menu while it already runs: how things stand, and Check now
        public static int Status()
        {
            var s = Settings.Load();
            var f = Wow.Resolve(s);
            using (var w = new WolfWindow())
            {
                Func<Page> make = null;
                make = () =>
                {
                    var p = new Page { Title = App.Name, Subtitle = "running by your clock - version " + App.Version };
                    if (f == null)
                    {
                        p.Body = "It can't find The Wolf of Booty Bay in World of Warcraft's folder. Install the addon, then start Wolf prices again.";
                    }
                    else
                    {
                        long ready = Prices.Times(f.FeedFile).T, inGame = Prices.InGame(f);
                        p.Body = "It checks for new prices every 15 minutes, quietly.";
                        p.Rows.Add(new Row { Ok = true, Label = "In your addon folder", Detail = "Blizzard's prices of " + Fmt.Time(ready) });
                        p.Rows.Add(new Row { Ok = inGame >= ready || inGame == 0, Label = "In game",
                            Detail = inGame == 0 ? "not seen yet (log in once)" : (inGame >= ready ? Fmt.Time(inGame) + ", up to date" : Fmt.Time(inGame) + " - /reload loads the newer ones") });
                        p.Buttons.Add(new Button_ { Text = "Check now", Click = () =>
                        {
                            w.Cursor = Cursors.WaitCursor;
                            var r = Prices.Check(f);
                            w.Cursor = Cursors.Default;
                            var np = make();
                            np.Footer = r.Ok ? (r.Downloaded ? "New prices downloaded." : "Checked: nothing newer yet.") : "Couldn't check (offline?).";
                            w.SetPage(np);
                        } });
                    }
                    p.Buttons.Add(new Button_ { Text = "Close", Primary = true, Click = () => w.Close() });
                    return p;
                };
                w.SetPage(make());
                Application.Run(w);
            }
            return 0;
        }
    }
}
