// Wolf prices: by the clock. A wolf in the tray, a check every 15 minutes, and nothing else: no notifications, no
// sounds, no windows (streams stay clean). Hover: when your prices are from. Right-click: Check now, Open the addon
// folder, Start with Windows, Quit. It updates itself quietly when a new version is out.
using System;
using System.Diagnostics;
using System.Drawing;
using System.Threading;
using System.Windows.Forms;

namespace WolfPrices
{
    class Tray : ApplicationContext
    {
        readonly NotifyIcon icon;
        readonly ToolStripMenuItem status, startup, keepUpdated;
        readonly System.Windows.Forms.Timer every, selfCheck, waitGame;
        readonly Control ui; // for coming back to the window thread
        readonly Settings settings = Settings.Load();
        Found found;
        int busy;

        Tray()
        {
            ui = new Control();
            ui.CreateControl();

            var menu = new ContextMenuStrip { Renderer = new DarkRenderer(), ShowImageMargin = false, Font = Theme.Body(9.5f) };
            var head = new ToolStripMenuItem(App.Name + " " + App.Version) { Enabled = false, Font = Theme.Semi(9.5f) };
            status = new ToolStripMenuItem("Checking...") { Enabled = false };
            menu.Items.Add(head);
            menu.Items.Add(status);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Check now", null, (s, e) => Check());
            menu.Items.Add("Open the addon folder", null, (s, e) => { if (found != null) Process.Start("explorer.exe", "\"" + found.Addon + "\""); });
            startup = new ToolStripMenuItem("Start with Windows") { CheckOnClick = true };
            try { startup.Checked = Installer.StartsWithWindows; } catch { }
            startup.Click += (s, e) => { try { Installer.StartsWithWindows = startup.Checked; } catch (Exception x) { Log.Write("startup: " + x.Message); } };
            menu.Items.Add(startup);
            // (1.1) Wolf itself, kept up to date: swapped in while you play, a /reload loads it
            keepUpdated = new ToolStripMenuItem("Keep Wolf updated") { CheckOnClick = true, Checked = settings.AutoUpdate };
            keepUpdated.Click += (s, e) => { settings.AutoUpdate = keepUpdated.Checked; settings.Save(); };
            menu.Items.Add(keepUpdated);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Quit", null, (s, e) => Quit());

            icon = new NotifyIcon { Icon = Theme.AppIcon(SystemInformation.SmallIconSize.Width), Text = App.Name + ": starting", ContextMenuStrip = menu, Visible = true };
            icon.MouseDoubleClick += (s, e) => Check();

            every = new System.Windows.Forms.Timer { Interval = App.EveryMinutes * 60 * 1000 };
            every.Tick += (s, e) => Check();
            every.Start();
            var first = new System.Windows.Forms.Timer { Interval = 3000 };
            first.Tick += (s, e) => { first.Stop(); first.Dispose(); Check(); };
            first.Start();

            // (1.1.2) a Wolf waiting for the game to close: looked at every minute, and put in once it's closed
            waitGame = new System.Windows.Forms.Timer { Interval = 60 * 1000 };
            waitGame.Tick += (s, e) =>
            {
                if (AddonUpdate.Last.Pending == null || found == null || busy == 1) return;
                ThreadPool.QueueUserWorkItem(_ => { if (!AddonUpdate.GameRunning(found)) Back(Check); });
            };
            waitGame.Start();

            // its own updates: a minute after starting, then every 6 hours
            selfCheck = new System.Windows.Forms.Timer { Interval = 60 * 1000 };
            selfCheck.Tick += (s, e) => { selfCheck.Interval = 6 * 3600 * 1000; SelfUpdate(); };
            selfCheck.Start();
        }

        void Check()
        {
            if (Interlocked.Exchange(ref busy, 1) == 1) return;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                string line;
                try
                {
                    if (found == null || !System.IO.File.Exists(System.IO.Path.Combine(found.Addon, "WolfOfBootyBay.toc"))) found = Wow.Resolve(settings);
                    if (found == null) line = "can't find the addon";
                    else
                    {
                        var r = Prices.Check(found, settings);
                        var ready = Fmt.Time(r.Ready);
                        if (!r.Ok) line = "offline? prices of " + ready;
                        else if (r.Updated != null) line = "Wolf " + r.Updated + " is in: /reload";
                        else if (r.Pending != null) line = "Wolf " + r.Pending + " goes in when the game closes";
                        else if (r.InGame > 0 && r.InGame >= r.Ready) line = "up to date (" + ready + ")";
                        else if (r.InGame > 0) line = "newer prices ready (" + ready + "), /reload";
                        else line = "prices of " + ready;
                    }
                }
                catch (Exception e) { line = "couldn't check"; Log.Write("check: " + e); }
                Back(() =>
                {
                    status.Text = Cap(line, 60);
                    icon.Text = Cap(App.Name + ": " + line, 63); // the tray's hover takes 63 letters
                    Interlocked.Exchange(ref busy, 0);
                });
            });
        }

        void SelfUpdate()
        {
            ThreadPool.QueueUserWorkItem(_ =>
            {
                try
                {
                    if (Installer.UpdateReady()) Back(Restart);
                }
                catch (Exception e) { Log.Write("update check: " + e.Message); }
            });
        }

        void Restart()
        {
            Close();
            try
            {
                Process.Start(new ProcessStartInfo(App.InstalledExe, "--tray --updated") { UseShellExecute = false, WorkingDirectory = App.InstallDir });
            }
            catch (Exception e) { Log.Write("restart after update: " + e.Message); }
            ExitThread();
        }

        static string Cap(string s, int n) { return s.Length > n ? s.Substring(0, n) : s; }

        void Back(Action a)
        {
            try { if (!ui.IsDisposed) ui.BeginInvoke(a); } catch { }
        }

        void Close()
        {
            every.Stop();
            selfCheck.Stop();
            waitGame.Stop();
            icon.Visible = false;
            icon.Dispose();
            if (mutex != null) { try { mutex.ReleaseMutex(); } catch { } mutex.Dispose(); mutex = null; }
        }

        void Quit()
        {
            Close();
            ExitThread();
        }

        static Mutex mutex;

        public static int Run(bool updated)
        {
            bool created = false;
            for (int i = 0; i < (updated ? 40 : 1); i++)
            {
                mutex = new Mutex(true, Installer.MutexName, out created);
                if (created) break;
                mutex.Dispose();
                mutex = null;
                Thread.Sleep(250);
            }
            if (!created) return Setup.Status(); // already by the clock: how things stand
            if (App.IsInstalledCopy) Installer.CleanUpOld();
            Log.Write("started " + App.Version + (updated ? " (updated)" : ""));
            var tray = new Tray();
            // setup or an uninstall asks it to quit
            var quit = new EventWaitHandle(false, EventResetMode.AutoReset, Installer.QuitName);
            ThreadPool.RegisterWaitForSingleObject(quit, (s, timedOut) => tray.Back(tray.Quit), null, -1, true);
            Application.Run(tray);
            quit.Dispose();
            return 0;
        }
    }

    // the menu in the window's colours
    class DarkRenderer : ToolStripProfessionalRenderer
    {
        public DarkRenderer() : base(new DarkColors()) { RoundedEdges = false; }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = !e.Item.Enabled ? (e.Item.Font.Bold || e.Item.Font.Name.Contains("Semibold") ? Theme.Gold : Theme.Muted) : Theme.Text;
            base.OnRenderItemText(e);
        }
        protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
        {
            var r = new Rectangle(e.ImageRectangle.X, e.ImageRectangle.Y, e.ImageRectangle.Width, e.ImageRectangle.Height);
            using (var pen = new Pen(Theme.Gold, 2)) e.Graphics.DrawLines(pen, new[] { new Point(r.X + 3, r.Y + r.Height / 2), new Point(r.X + r.Width / 2 - 1, r.Bottom - 4), new Point(r.Right - 3, r.Y + 4) });
        }
    }

    class DarkColors : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground { get { return Theme.Bg; } }
        public override Color MenuBorder { get { return Theme.Edge; } }
        public override Color MenuItemBorder { get { return Theme.GoldDim; } }
        public override Color MenuItemSelected { get { return Color.FromArgb(48, 38, 22); } }
        public override Color MenuItemSelectedGradientBegin { get { return Color.FromArgb(48, 38, 22); } }
        public override Color MenuItemSelectedGradientEnd { get { return Color.FromArgb(48, 38, 22); } }
        public override Color SeparatorDark { get { return Theme.Edge; } }
        public override Color SeparatorLight { get { return Theme.Bg; } }
        public override Color ImageMarginGradientBegin { get { return Theme.Bg; } }
        public override Color ImageMarginGradientMiddle { get { return Theme.Bg; } }
        public override Color ImageMarginGradientEnd { get { return Theme.Bg; } }
        public override Color CheckBackground { get { return Theme.Bg; } }
        public override Color CheckSelectedBackground { get { return Color.FromArgb(48, 38, 22); } }
        public override Color CheckPressedBackground { get { return Color.FromArgb(48, 38, 22); } }
    }
}
