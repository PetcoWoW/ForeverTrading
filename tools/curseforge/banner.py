from PIL import Image, ImageDraw, ImageFont, ImageFilter
W,H,S=1200,300,2
img=Image.new("RGB",(W*S,H*S))
d=ImageDraw.Draw(img)
for y in range(H*S):
    t=y/(H*S); d.line([(0,y),(W*S,y)],fill=(int(46-18*t),int(34-14*t),int(22-9*t)))
d.rounded_rectangle([6*S,6*S,(W-6)*S,(H-6)*S],radius=26*S,outline=(201,160,82),width=4*S)
F="/usr/share/fonts/truetype/google-fonts/"
bold=lambda n: ImageFont.truetype(F+"Poppins-Bold.ttf",n*S)
reg=lambda n: ImageFont.truetype(F+"Poppins-Regular.ttf",n*S)
semi=lambda n: ImageFont.truetype(F+"Poppins-Medium.ttf",n*S)
logo=Image.open("/home/claude/wolflogo/curseforge/wolf-curseforge-round-400.png").convert("RGBA").resize((200*S,200*S),Image.LANCZOS)
img.paste(logo,(40*S,50*S),logo)
x=272*S
d.text((x,40*S),"STEP 1  ·  BEFORE ANYTHING ELSE",font=semi(22),fill=(201,160,82))
d.text((x,70*S),"Get the Wolf prices app",font=bold(52),fill=(246,236,214))
d.text((x,140*S),"Without it, Wolf only knows the prices you scan yourself.",font=reg(24),fill=(214,198,170))
bx0,by0,bx1,by1=x,190*S,x+560*S,256*S
sh=Image.new("RGBA",img.size,(0,0,0,0)); sd=ImageDraw.Draw(sh)
sd.rounded_rectangle([bx0,by0+6*S,bx1,by1+6*S],radius=16*S,fill=(0,0,0,150))
sh=sh.filter(ImageFilter.GaussianBlur(6*S)); img.paste(sh,(0,0),sh); d=ImageDraw.Draw(img)
d.rounded_rectangle([bx0,by0,bx1,by1],radius=16*S,fill=(70,156,66),outline=(150,214,120),width=2*S)
ax,ay=bx0+40*S,by0+33*S
d.polygon([(ax-14*S,ay-2*S),(ax+14*S,ay-2*S),(ax,ay+16*S)],fill=(255,255,255))
d.rectangle([ax-6*S,ay-20*S,ax+6*S,ay-2*S],fill=(255,255,255))
d.text((bx0+72*S,by0+13*S),"Download WolfPricesSetup.exe",font=bold(28),fill=(255,255,255))
d.text((bx1+24*S,by0+8*S),"Windows · free",font=semi(22),fill=(246,236,214))
d.text((bx1+24*S,by0+36*S),"install once, forget it",font=reg(20),fill=(214,198,170))
img.resize((W,H),Image.LANCZOS).save("/home/claude/cfdesc/download-banner.png",optimize=True)
