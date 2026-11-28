# The CurseForge page's banner (v0.61): the wolf, the name, what it is, and that it works with Auctionator.
# python3 tools/curseforge/banner.py <logo png> <out png>
import sys
from PIL import Image, ImageDraw, ImageFont
W, H, S = 1200, 300, 2
img = Image.new("RGB", (W * S, H * S))
d = ImageDraw.Draw(img)
for y in range(H * S):
    t = y / (H * S); d.line([(0, y), (W * S, y)], fill=(int(46 - 18 * t), int(34 - 14 * t), int(22 - 9 * t)))
d.rounded_rectangle([6 * S, 6 * S, (W - 6) * S, (H - 6) * S], radius=26 * S, outline=(201, 160, 82), width=4 * S)
F = "/usr/share/fonts/truetype/google-fonts/"
bold = lambda n: ImageFont.truetype(F + "Poppins-Bold.ttf", n * S)
reg = lambda n: ImageFont.truetype(F + "Poppins-Regular.ttf", n * S)
med = lambda n: ImageFont.truetype(F + "Poppins-Medium.ttf", n * S)
logo = Image.open(sys.argv[1]).convert("RGBA").resize((200 * S, 200 * S), Image.LANCZOS)
img.paste(logo, (40 * S, 50 * S), logo)
x = 272 * S
d.text((x, 40 * S), "FOR WOW FOREVER", font=med(22), fill=(201, 160, 82))
d.text((x, 70 * S), "Wolf: the auction house", font=bold(48), fill=(246, 236, 214))
d.text((x, 132 * S), "as a stock market. What to buy, sell, craft and farm, in plain English.", font=reg(22), fill=(214, 198, 170))
cx = x
for chip in ["Works with Auctionator", "Free", "Safe on stream"]:
    w = d.textlength(chip, font=med(22)) + 36 * S
    d.rounded_rectangle([cx, 196 * S, cx + w, 246 * S], radius=14 * S, fill=(70, 156, 66) if chip == "Works with Auctionator" else (62, 50, 34), outline=(150, 214, 120) if chip == "Works with Auctionator" else (120, 96, 60), width=2 * S)
    d.text((cx + 18 * S, 205 * S), chip, font=med(22), fill=(255, 255, 255))
    cx += w + 14 * S
img.resize((W, H), Image.LANCZOS).save(sys.argv[2], optimize=True)
