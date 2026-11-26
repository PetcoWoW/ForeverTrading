// Wolf prices: its look. One window drawn by hand in the addon's colours (night brown, Booty Bay gold): the wolf
// in a gold ring, a title, a few lines, ticks for what was found, and gold buttons. Used for setup, the status
// window and the two small questions (remove it?). Nothing here pops up on its own: only when you start something.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace WolfPrices
{
    static class Theme
    {
        public static readonly Color Bg = Color.FromArgb(21, 18, 14);
        public static readonly Color BgTop = Color.FromArgb(38, 30, 19);
        public static readonly Color Edge = Color.FromArgb(78, 62, 34);
        public static readonly Color Gold = Color.FromArgb(240, 185, 11);
        public static readonly Color GoldHot = Color.FromArgb(255, 210, 74);
        public static readonly Color GoldDim = Color.FromArgb(150, 116, 40);
        public static readonly Color GoldOff = Color.FromArgb(84, 70, 38);
        public static readonly Color Ink = Color.FromArgb(26, 20, 8);
        public static readonly Color Text = Color.FromArgb(237, 227, 204);
        public static readonly Color Muted = Color.FromArgb(168, 156, 132);
        public static readonly Color Dim = Color.FromArgb(118, 108, 90);
        public static readonly Color Good = Color.FromArgb(108, 194, 74);
        public static readonly Color Bad = Color.FromArgb(224, 87, 79);

        static Image wolf;
        public static Image Wolf
        {
            get
            {
                if (wolf == null)
                {
                    using (var s = typeof(Theme).Assembly.GetManifestResourceStream("wolf.ico"))
                    using (var ic = new Icon(s, 256, 256))
                        wolf = ic.ToBitmap();
                }
                return wolf;
            }
        }

        public static Icon AppIcon(int size)
        {
            using (var s = typeof(Theme).Assembly.GetManifestResourceStream("wolf.ico"))
                return new Icon(s, size, size);
        }

        public static Font Title(float pt) { return new Font(Has("Georgia") ? "Georgia" : "Times New Roman", pt, FontStyle.Bold); }
        public static Font Body(float pt, FontStyle st = FontStyle.Regular) { return new Font("Segoe UI", pt, st); }
        public static Font Semi(float pt) { return new Font(Has("Segoe UI Semibold") ? "Segoe UI Semibold" : "Segoe UI", pt, Has("Segoe UI Semibold") ? FontStyle.Regular : FontStyle.Bold); }

        static bool Has(string family)
        {
            foreach (var f in FontFamily.Families) if (f.Name == family) return true;
            return false;
        }

        public static GraphicsPath Round(RectangleF r, float rad)
        {
            var p = new GraphicsPath();
            float d = rad * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
    }

    class Button_
    {
        public string Text;
        public bool Primary;
        public bool Enabled = true;
        public Action Click;
        public RectangleF Rect;
    }

    class Row
    {
        public bool Ok;
        public string Label;
        public string Detail;
        public Button_ Link; // a gold word on the right ("Pick folder...")
    }

    class Page
    {
        public string Title;
        public string Subtitle;
        public string Body;
        public List<Row> Rows = new List<Row>();
        public string CheckText;
        public bool Checked;
        public string Footer;
        public List<Button_> Buttons = new List<Button_>();
        public bool Compact; // the small questions
    }

    class WolfWindow : Form
    {
        Page page;
        float k = 1f;
        object hover;
        RectangleF closeRect, checkRect;
        readonly List<Button_> links = new List<Button_>();
        public bool CheckValue { get { return page != null && page.Checked; } }

        public WolfWindow()
        {
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            DoubleBuffered = true;
            BackColor = Theme.Bg;
            Text = App.Name;
            KeyPreview = true;
            try { Icon = Theme.AppIcon(32); } catch { }
            using (var g = CreateGraphics()) k = g.DpiX / 96f;
        }

        float S(float v) { return v * k; }

        public void SetPage(Page p)
        {
            page = p;
            ClientSize = p.Compact ? new Size((int)S(470), (int)S(250)) : new Size((int)S(560), (int)S(430));
            if (Visible) CenterToScreen();
            Invalidate();
        }

        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.ClassStyle |= 0x20000; // a shadow
                return cp;
            }
        }

        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        [DllImport("user32.dll")] static extern bool ReleaseCapture();
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wp, IntPtr lp);

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            try { int round = 2; DwmSetWindowAttribute(Handle, 33, ref round, 4); } catch { } // Windows 11's round corners
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (page == null) return;
            if (e.KeyCode == Keys.Escape) { Close(); return; }
            if (e.KeyCode == Keys.Enter)
                foreach (var b in page.Buttons) if (b.Primary && b.Enabled && b.Click != null) { b.Click(); return; }
        }

        object HitTest(Point pt)
        {
            if (closeRect.Contains(pt)) return "close";
            if (page == null) return null;
            foreach (var b in page.Buttons) if (b.Enabled && b.Rect.Contains(pt)) return b;
            foreach (var b in links) if (b.Enabled && b.Rect.Contains(pt)) return b;
            if (page.CheckText != null && checkRect.Contains(pt)) return "check";
            return null;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            var h = HitTest(e.Location);
            if (!Equals(h, hover)) { hover = h; Cursor = h != null ? Cursors.Hand : Cursors.Default; Invalidate(); }
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            if (hover != null) { hover = null; Invalidate(); }
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;
            var h = HitTest(e.Location);
            if (h == null)
            {
                // drag the window by anything else
                ReleaseCapture();
                SendMessage(Handle, 0xA1, (IntPtr)2, IntPtr.Zero);
                return;
            }
            if (Equals(h, "close")) { Close(); return; }
            if (Equals(h, "check")) { page.Checked = !page.Checked; Invalidate(); return; }
            var b = h as Button_;
            if (b != null && b.Click != null) b.Click();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            var W = ClientSize.Width;
            var H = ClientSize.Height;
            g.Clear(Theme.Bg);
            using (var top = new LinearGradientBrush(new Rectangle(0, 0, W, (int)S(170)), Theme.BgTop, Theme.Bg, 90f))
                g.FillRectangle(top, 0, 0, W, S(170));
            using (var edge = new Pen(Theme.Edge, 1)) g.DrawRectangle(edge, 0, 0, W - 1, H - 1);
            if (page == null) return;
            links.Clear();

            // close
            closeRect = new RectangleF(W - S(40), S(10), S(30), S(30));
            using (var pen = new Pen(Equals(hover, "close") ? Theme.Text : Theme.Dim, S(1.6f)))
            {
                float c = S(5);
                var r = closeRect;
                g.DrawLine(pen, r.X + r.Width / 2 - c, r.Y + r.Height / 2 - c, r.X + r.Width / 2 + c, r.Y + r.Height / 2 + c);
                g.DrawLine(pen, r.X + r.Width / 2 + c, r.Y + r.Height / 2 - c, r.X + r.Width / 2 - c, r.Y + r.Height / 2 + c);
            }

            // the wolf in a gold ring
            float m = page.Compact ? S(64) : S(104);
            var medal = new RectangleF(S(30), S(28), m, m);
            using (var path = new GraphicsPath())
            {
                path.AddEllipse(medal);
                using (var pg = new PathGradientBrush(path) { CenterColor = Color.FromArgb(64, 50, 24), SurroundColors = new[] { Color.FromArgb(24, 19, 12) } })
                    g.FillEllipse(pg, medal);
            }
            using (var ring = new Pen(Theme.GoldDim, S(2))) g.DrawEllipse(ring, medal);
            using (var ring2 = new Pen(Color.FromArgb(90, Theme.Gold), S(1))) g.DrawEllipse(ring2, RectangleF.Inflate(medal, -S(5), -S(5)));
            float wi = m * 0.74f;
            g.DrawImage(Theme.Wolf, medal.X + (m - wi) / 2, medal.Y + (m - wi) / 2, wi, wi);

            // title and subtitle
            float tx = medal.Right + S(22);
            using (var tf = Theme.Title(page.Compact ? 15 : 21))
                TextRenderer.DrawText(g, page.Title ?? "", tf, new Point((int)tx, (int)(medal.Y + (page.Compact ? S(6) : S(18)))), Theme.Gold, TextFormatFlags.NoPadding);
            if (page.Subtitle != null)
                using (var sf = Theme.Body(10))
                    TextRenderer.DrawText(g, page.Subtitle, sf, new Point((int)(tx + S(1)), (int)(medal.Y + (page.Compact ? S(36) : S(58)))), Theme.Muted, TextFormatFlags.NoPadding);

            // the words
            float y = page.Compact ? medal.Bottom + S(16) : medal.Bottom + S(26);
            float left = S(32), width = W - S(64);
            if (page.Compact) { left = tx; width = W - tx - S(30); y = medal.Y + S(40); }
            if (!string.IsNullOrEmpty(page.Body))
            {
                using (var bf = Theme.Body(10.5f))
                {
                    var flags = TextFormatFlags.WordBreak | TextFormatFlags.NoPadding;
                    var size = TextRenderer.MeasureText(g, page.Body, bf, new Size((int)width, 1000), flags);
                    TextRenderer.DrawText(g, page.Body, bf, new Rectangle((int)left, (int)y, (int)width, size.Height + 4), Theme.Text, flags);
                    y += size.Height + S(20);
                }
            }

            // what was found
            foreach (var row in page.Rows)
            {
                var dot = new RectangleF(left, y + S(2), S(18), S(18));
                using (var b = new SolidBrush(row.Ok ? Theme.Good : Theme.Bad)) g.FillEllipse(b, dot);
                using (var pen = new Pen(Theme.Ink, S(2)) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                {
                    if (row.Ok)
                        g.DrawLines(pen, new[] { new PointF(dot.X + S(4.5f), dot.Y + S(9.5f)), new PointF(dot.X + S(7.8f), dot.Y + S(12.8f)), new PointF(dot.X + S(13.5f), dot.Y + S(6)) });
                    else
                    {
                        g.DrawLine(pen, dot.X + S(9), dot.Y + S(4.5f), dot.X + S(9), dot.Y + S(10.5f));
                        g.DrawLine(pen, dot.X + S(9), dot.Y + S(13.6f), dot.X + S(9), dot.Y + S(13.8f));
                    }
                }
                float x = dot.Right + S(10);
                using (var lf = Theme.Semi(10))
                {
                    TextRenderer.DrawText(g, row.Label, lf, new Point((int)x, (int)(y + S(1))), Theme.Text, TextFormatFlags.NoPadding);
                    x += TextRenderer.MeasureText(g, row.Label, lf, Size.Empty, TextFormatFlags.NoPadding).Width + S(8);
                }
                float right = left + width;
                if (row.Link != null)
                {
                    using (var kf = Theme.Body(10, FontStyle.Underline))
                    {
                        var ls = TextRenderer.MeasureText(g, row.Link.Text, kf, Size.Empty, TextFormatFlags.NoPadding);
                        row.Link.Rect = new RectangleF(right - ls.Width, y, ls.Width, S(22));
                        TextRenderer.DrawText(g, row.Link.Text, kf, new Point((int)row.Link.Rect.X, (int)(y + S(1))),
                            Equals(hover, row.Link) ? Theme.GoldHot : Theme.Gold, TextFormatFlags.NoPadding);
                        links.Add(row.Link);
                        right -= ls.Width + S(14);
                    }
                }
                if (!string.IsNullOrEmpty(row.Detail))
                    using (var df = Theme.Body(9.5f))
                        TextRenderer.DrawText(g, row.Detail, df, new Rectangle((int)x, (int)(y + S(2)), (int)Math.Max(10, right - x), (int)S(22)), Theme.Muted,
                            TextFormatFlags.NoPadding | TextFormatFlags.PathEllipsis | TextFormatFlags.SingleLine);
                y += S(32);
            }

            // the tick box
            if (page.CheckText != null)
            {
                y += S(4);
                var box = new RectangleF(left, y + S(1), S(18), S(18));
                using (var path = Theme.Round(box, S(4)))
                {
                    if (page.Checked) using (var b = new SolidBrush(Equals(hover, "check") ? Theme.GoldHot : Theme.Gold)) g.FillPath(b, path);
                    using (var pen = new Pen(page.Checked ? Theme.Gold : (Equals(hover, "check") ? Theme.Gold : Theme.GoldDim), S(1.4f))) g.DrawPath(pen, path);
                }
                if (page.Checked)
                    using (var pen = new Pen(Theme.Ink, S(2)) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                        g.DrawLines(pen, new[] { new PointF(box.X + S(4.5f), box.Y + S(9.5f)), new PointF(box.X + S(7.8f), box.Y + S(12.8f)), new PointF(box.X + S(13.5f), box.Y + S(6)) });
                using (var cf = Theme.Body(10.5f))
                {
                    TextRenderer.DrawText(g, page.CheckText, cf, new Point((int)(box.Right + S(10)), (int)y), Theme.Text, TextFormatFlags.NoPadding);
                    var cs = TextRenderer.MeasureText(g, page.CheckText, cf, Size.Empty, TextFormatFlags.NoPadding);
                    checkRect = new RectangleF(box.X - S(2), box.Y - S(3), cs.Width + S(34), S(24));
                }
            }

            // buttons, right to left
            float bx = W - S(28), by = H - S(26) - S(38);
            for (int i = page.Buttons.Count - 1; i >= 0; i--)
            {
                var b = page.Buttons[i];
                using (var bf = b.Primary ? Theme.Semi(10.5f) : Theme.Body(10.5f))
                {
                    var ts = TextRenderer.MeasureText(g, b.Text, bf, Size.Empty, TextFormatFlags.NoPadding);
                    float bw = Math.Max(S(104), ts.Width + S(40));
                    b.Rect = new RectangleF(bx - bw, by, bw, S(38));
                    bx -= bw + S(10);
                    bool hot = Equals(hover, b);
                    using (var path = Theme.Round(b.Rect, S(6)))
                    {
                        if (b.Primary)
                        {
                            var c = !b.Enabled ? Theme.GoldOff : (hot ? Theme.GoldHot : Theme.Gold);
                            using (var fill = new LinearGradientBrush(b.Rect, ControlPaint.Light(c, 0.15f), c, 90f)) g.FillPath(fill, path);
                        }
                        else
                        {
                            using (var pen = new Pen(hot ? Theme.Gold : Theme.Edge, S(1.2f))) g.DrawPath(pen, path);
                        }
                    }
                    var fg = b.Primary ? (b.Enabled ? Theme.Ink : Color.FromArgb(40, 33, 18)) : (hot ? Theme.Text : Theme.Muted);
                    TextRenderer.DrawText(g, b.Text, bf, Rectangle.Round(b.Rect), fg,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                }
            }

            // the small print
            if (!string.IsNullOrEmpty(page.Footer))
                using (var ff = Theme.Body(8.5f))
                    TextRenderer.DrawText(g, page.Footer, ff, new Rectangle((int)S(32), (int)(by), (int)(bx - S(40)), (int)S(38)), Theme.Dim,
                        TextFormatFlags.WordBreak | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }

        // a picture of a page, for the build's check (no window on screen)
        public Bitmap Picture()
        {
            CreateControl();
            var bmp = new Bitmap(ClientSize.Width, ClientSize.Height);
            using (var g = Graphics.FromImage(bmp))
                OnPaint(new PaintEventArgs(g, new Rectangle(Point.Empty, ClientSize)));
            return bmp;
        }
    }

    static class Ui
    {
        public static bool Ask(string title, string body, string yes, string no)
        {
            using (var w = new WolfWindow())
            {
                bool answer = false;
                var p = new Page { Title = title, Body = body, Compact = true };
                p.Buttons.Add(new Button_ { Text = no, Click = () => w.Close() });
                p.Buttons.Add(new Button_ { Text = yes, Primary = true, Click = () => { answer = true; w.Close(); } });
                w.SetPage(p);
                w.ShowDialog();
                return answer;
            }
        }

        public static void Tell(string title, string body)
        {
            using (var w = new WolfWindow())
            {
                var p = new Page { Title = title, Body = body, Compact = true };
                p.Buttons.Add(new Button_ { Text = "OK", Primary = true, Click = () => w.Close() });
                w.SetPage(p);
                w.ShowDialog();
            }
        }
    }
}
