// Wolf prices: installing, starting with Windows, uninstalling, and updating itself. For this Windows user only
// (no admin rights): the program in %LOCALAPPDATA%\Programs\WolfPrices, a Start menu shortcut, an entry in
// Settings > Apps with an Uninstall button, and "start with Windows" as the usual Run entry.
using System;
using System.Diagnostics;
using System.IO;
using System.Management;
using System.Security.Cryptography;
using System.Threading;
using Microsoft.Win32;

namespace WolfPrices
{
    static class Installer
    {
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\WolfPrices";
        public const string MutexName = @"Local\WolfPricesCompanion";
        public const string QuitName = @"Local\WolfPricesQuit";

        static string StartMenuLink
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Wolf prices.lnk"); }
        }

        public static bool IsInstalled { get { return File.Exists(App.InstalledExe); } }

        public static bool StartsWithWindows
        {
            get
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey)) return k != null && k.GetValue("WolfPrices") != null;
            }
            set
            {
                using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (value) k.SetValue("WolfPrices", "\"" + App.InstalledExe + "\" --tray");
                    else if (k.GetValue("WolfPrices") != null) k.DeleteValue("WolfPrices");
                }
            }
        }

        public static void Install(bool startWithWindows)
        {
            StopRunning();
            StopFirstCompanion();
            Directory.CreateDirectory(App.InstallDir);
            if (!App.IsInstalledCopy)
            {
                var tmp = App.InstalledExe + ".new";
                File.Copy(App.SelfExe, tmp, true);
                if (File.Exists(App.InstalledExe)) File.Replace(tmp, App.InstalledExe, null);
                else File.Move(tmp, App.InstalledExe);
            }
            try { Shortcut(StartMenuLink, App.InstalledExe, "", "Wolf prices: fresh auction prices for The Wolf of Booty Bay"); }
            catch (Exception e) { Log.Write("start menu shortcut: " + e.Message); }
            StartsWithWindows = startWithWindows;
            using (var k = Registry.CurrentUser.CreateSubKey(UninstallKey))
            {
                k.SetValue("DisplayName", "Wolf prices (The Wolf of Booty Bay)");
                k.SetValue("DisplayVersion", App.Version);
                k.SetValue("Publisher", "The Wolf of Booty Bay");
                k.SetValue("DisplayIcon", App.InstalledExe);
                k.SetValue("InstallLocation", App.InstallDir);
                k.SetValue("UninstallString", "\"" + App.InstalledExe + "\" --uninstall");
                k.SetValue("QuietUninstallString", "\"" + App.InstalledExe + "\" --uninstall --quiet");
                k.SetValue("URLInfoAbout", "https://github.com/" + App.Repo);
                k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                k.SetValue("EstimatedSize", (int)Math.Max(1, new FileInfo(App.InstalledExe).Length / 1024), RegistryValueKind.DWord);
            }
            Log.Write("installed " + App.Version + " in " + App.InstallDir);
        }

        public static void Launch()
        {
            Process.Start(new ProcessStartInfo(App.InstalledExe, "--tray") { UseShellExecute = false, WorkingDirectory = App.InstallDir });
        }

        // the one running by the clock: asked to quit, then waited for
        public static void StopRunning()
        {
            try
            {
                EventWaitHandle quit;
                if (EventWaitHandle.TryOpenExisting(QuitName, out quit))
                {
                    quit.Set();
                    quit.Dispose();
                    for (int i = 0; i < 50; i++)
                    {
                        Mutex m;
                        if (!Mutex.TryOpenExisting(MutexName, out m)) break;
                        m.Dispose();
                        Thread.Sleep(100);
                    }
                }
            }
            catch (Exception e) { Log.Write("stop running: " + e.Message); }
        }

        // the first companion (a PowerShell script): its Startup shortcut removed, and stopped if it runs
        public static bool StopFirstCompanion()
        {
            bool any = false;
            try
            {
                var lnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "Wolf prices.lnk");
                if (File.Exists(lnk)) { File.Delete(lnk); any = true; }
            }
            catch { }
            try
            {
                using (var q = new ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name = 'powershell.exe'"))
                {
                    foreach (ManagementObject p in q.Get())
                    {
                        var cmd = p["CommandLine"] as string;
                        if (cmd != null && cmd.IndexOf("WolfPrices.ps1", StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            try { Process.GetProcessById(Convert.ToInt32(p["ProcessId"])).Kill(); any = true; } catch { }
                        }
                    }
                }
            }
            catch (Exception e) { Log.Write("first companion: " + e.Message); }
            if (any) Log.Write("the first companion (script) was stopped and removed");
            return any;
        }

        public static void Uninstall(bool quiet)
        {
            if (!quiet && !Ui.Ask("Remove Wolf prices?",
                "Your addon keeps working; prices then come only with addon updates.", "Remove", "Keep it")) return;
            StopRunning();
            try { StartsWithWindows = false; } catch { }
            try { if (File.Exists(StartMenuLink)) File.Delete(StartMenuLink); } catch { }
            try { Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false); } catch { }
            try
            {
                var f = Wow.Resolve(Settings.Load());
                if (f != null) Prices.ClearNote(f);
            }
            catch { }
            try { Directory.Delete(App.DataDir, true); } catch { }
            // a running program can't delete itself: a moment after it quits
            try
            {
                var psi = new ProcessStartInfo("cmd.exe", "/c ping 127.0.0.1 -n 3 > nul & rmdir /s /q \"" + App.InstallDir + "\"")
                { CreateNoWindow = true, UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden };
                Process.Start(psi);
            }
            catch { }
            if (!quiet) Ui.Tell("Wolf prices is removed.", "Thanks for running with the pack.");
        }

        static void Shortcut(string lnk, string target, string args, string description)
        {
            var t = Type.GetTypeFromProgID("WScript.Shell");
            var shell = Activator.CreateInstance(t);
            var sc = t.InvokeMember("CreateShortcut", System.Reflection.BindingFlags.InvokeMethod, null, shell, new object[] { lnk });
            var st = sc.GetType();
            st.InvokeMember("TargetPath", System.Reflection.BindingFlags.SetProperty, null, sc, new object[] { target });
            st.InvokeMember("Arguments", System.Reflection.BindingFlags.SetProperty, null, sc, new object[] { args });
            st.InvokeMember("WorkingDirectory", System.Reflection.BindingFlags.SetProperty, null, sc, new object[] { Path.GetDirectoryName(target) });
            st.InvokeMember("IconLocation", System.Reflection.BindingFlags.SetProperty, null, sc, new object[] { target + ",0" });
            st.InvokeMember("Description", System.Reflection.BindingFlags.SetProperty, null, sc, new object[] { description });
            st.InvokeMember("Save", System.Reflection.BindingFlags.InvokeMethod, null, sc, null);
        }

        // ------------------------------------------------------------------------------------------------------
        // Updating itself: a newer version in the companion's release (companion.json: version, sha256) is
        // downloaded, checked against its fingerprint, swapped in, and started; this one quits. Quietly.
        // ------------------------------------------------------------------------------------------------------
        public static string OldExe { get { return App.InstalledExe + ".old"; } }

        public static void CleanUpOld()
        {
            for (int i = 0; i < 20 && File.Exists(OldExe); i++)
            {
                try { File.Delete(OldExe); } catch { Thread.Sleep(250); }
            }
        }

        // true: a new version is in place (the caller starts it and quits)
        public static bool UpdateReady()
        {
            if (!App.IsInstalledCopy) return false;
            var info = Prices.Get(App.SelfInfoUrl, 30);
            var latest = Prices.JsonString(info, "version");
            var sha = (Prices.JsonString(info, "sha256") ?? "").ToLowerInvariant();
            Version want, have;
            if (latest == null || sha.Length != 64 || !System.Version.TryParse(latest, out want) || !System.Version.TryParse(App.Version, out have)) return false;
            if (want <= have) return false;
            var tmp = App.InstalledExe + ".download";
            Prices.Download(App.SelfExeUrl, tmp, 120);
            string got;
            using (var s = File.OpenRead(tmp))
            using (var h = SHA256.Create())
                got = BitConverter.ToString(h.ComputeHash(s)).Replace("-", "").ToLowerInvariant();
            if (got != sha)
            {
                File.Delete(tmp);
                Log.Write("update " + latest + ": the download didn't match its fingerprint, kept " + App.Version);
                return false;
            }
            CleanUpOld();
            File.Move(App.InstalledExe, OldExe);
            File.Move(tmp, App.InstalledExe);
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(UninstallKey, true))
                    if (k != null) k.SetValue("DisplayVersion", latest);
            }
            catch { }
            Log.Write("updated " + App.Version + " -> " + latest);
            return true;
        }
    }
}
