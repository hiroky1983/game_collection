import os
from PIL import Image, ImageFilter, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
S = os.path.dirname(HERE)  # docs/design/hub-redesign-1831（このスクリプト自身の位置基準）
SH=f"{S}/shots"  # 実機/シミュレータのスクショ置き場。このモック一式には同梱していないので再生成時に用意する
OUT=f"{S}/hub-redesign/assets/tiles"
W,H=537,645  # 179x215pt @3x

def cover(im, w=W, h=H):
    r=max(w/im.width, h/im.height)
    im=im.resize((round(im.width*r), round(im.height*r)), Image.LANCZOS)
    x=(im.width-w)//2; y=(im.height-h)//2
    return im.crop((x,y,x+w,y+h))

def shot(name): return Image.open(f"{SH}/{name}.png").convert("RGB")

def simple(name, box, src=None):
    im=(src or shot(name)).crop(box)
    cover(im).save(f"{OUT}/{name}.jpg", quality=90)

def composite(name, bg, parts):
    """bg: hex; parts: list of (crop_box, width_ratio, anchor_y_ratio, src_name)"""
    tile=Image.new("RGB",(W,H),bg)
    # soft blurred backdrop of the whole screen for texture
    base=cover(shot(name)).filter(ImageFilter.GaussianBlur(28))
    tile=Image.blend(tile, base, 0.35)
    for box, wr, ay, srcn in parts:
        p=shot(srcn or name).crop(box)
        w=int(W*wr); p=p.resize((w, int(p.height*w/p.width)), Image.LANCZOS)
        # drop shadow
        sh=Image.new("RGBA",(p.width+40,p.height+40),(0,0,0,0))
        ImageDraw.Draw(sh).rounded_rectangle((20,20,p.width+20,p.height+20),16,fill=(0,0,0,110))
        sh=sh.filter(ImageFilter.GaussianBlur(12))
        x=(W-p.width)//2; y=int(H*ay)-p.height//2
        tile.paste(sh,(x-20,y-14),sh)
        tile.paste(p,(x,y))
    tile.save(f"{OUT}/{name}.jpg", quality=90)

simple("shogi",(330,950,1030,1790))
simple("othello",(330,820,1030,1660))
simple("gomoku",(330,1300,1030,2140))
simple("2048",(100,700,850,1600))
simple("fifteen",(200,1050,950,1950))
simple("minesweeper",(60,1080,760,1920))
simple("solitaire",(250,560,950,1400))
simple("runner",(200,950,900,1790))
simple("ojisanpuzzle",(100,700,1060,2040))
simple("sudoku",(60,620,760,1460))
simple("mahjong4",(200,1000,1050,2020))
simple("go",(260,820,960,1660))
simple("chess",(60,1000,760,1840))
hero=Image.open(f"{S}/hub-redesign/assets/HomerunHubHeroArtLogo.jpg").convert("RGB")
simple("homerun",(350,250,1000,1024),src=hero)
composite("poker","#1E8C72",[((60,1400,1150,1680),0.92,0.72,None),((60,670,1150,940),0.80,0.30,None)])
composite("daifugo","#6A4BC8",[((60,1740,1150,2110),0.95,0.70,None),((470,1220,740,1430),0.30,0.26,None)])
composite("blackjack","#C04A3A",[((380,650,830,1000),0.62,0.32,None),((380,1640,830,1960),0.62,0.74,None)])
print("ok")
