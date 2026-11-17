
import os, math, random
from PIL import Image, ImageDraw

ROOT = "/Users/qwe/Documents/文件大总管/10-项目/幸存者游戏"
SPR = os.path.join(ROOT, "assets/sprites")
ICO = os.path.join(ROOT, "assets/icons")
os.makedirs(SPR, exist_ok=True)
os.makedirs(ICO, exist_ok=True)

PAL = ["#00000000","#0B0F16","#1C2330","#2E3A4C","#4A5568","#6B7280","#8C7A5B","#B89A6A",
       "#D9C08A","#E0B85A","#F2E3B8","#7C3A2E","#B4472F","#3E6B4F","#6E8B5A","#2B4C6F",
       "#4A7FA8","#8E5AA0","#5C3A52","#C86B3C"]
# indices
K0,K1,K2,K3,K4,K5,K6,K7,K8,K9,K10,K11,K12,K13,K14,K15,K16,K17,K18,K19 = range(20)

def new(w,h): return Image.new("RGBA",(w,h),(0,0,0,0))
def px(d,x,y,c):
    if 0<=x<d.im.size[0] and 0<=y<d.im.size[1]: d.point((x,y),c)
def rect(d,x0,y0,x1,y1,c): d.rectangle([x0,y0,x1,y1],fill=c)
def ell(d,x0,y0,x1,y1,c): d.ellipse([x0,y0,x1,y1],fill=c)
def line(d,x0,y0,x1,y1,c,w=1): d.line([x0,y0,x1,y1],fill=c,width=w)

P = PAL
def C(i): return P[i]


from PIL import ImageFilter
def outline(fr, col=(11,15,22,255)):
    a = fr.split()[3]
    dil = a.filter(ImageFilter.MaxFilter(3))
    ol = Image.new("RGBA", fr.size, col)
    ol.putalpha(dil)
    out = Image.new("RGBA", fr.size, (0,0,0,0))
    out.alpha_composite(ol)
    out.alpha_composite(fr)
    return out

# ---------------- humanoids (32x32, feet at y=29) ----------------
def humanoid(d, bob, legphase, skin, cloth, cloth2, metal, prop, eye=K1):
    by = bob
    # shadow
    ell(d, 10, 28, 22, 31, (0,0,0,90))
    # legs
    l = legphase
    rect(d, 12, 22+by+l, 14, 28+by, C(cloth2))
    rect(d, 17, 22+by-l, 19, 28+by, C(cloth2))
    rect(d, 12, 27+by, 14, 28+by, C(K1)); rect(d, 17, 27+by, 19, 28+by, C(K1))
    # body
    rect(d, 11, 14+by, 20, 22+by, C(cloth))
    rect(d, 11, 14+by, 12, 22+by, C(cloth2))   # shading
    rect(d, 11, 21+by, 20, 22+by, C(metal) if metal is not None else C(cloth2))  # belt
    # arms
    rect(d, 9, 15+by, 11, 21+by, C(cloth2))
    rect(d, 20, 15+by, 22, 21+by, C(cloth2))
    # head
    ell(d, 12, 6+by, 19, 14+by, C(skin))
    rect(d, 13, 6+by, 18, 8+by, C(K11))   # hair
    px(d, 14, 10+by, C(eye)); px(d, 17, 10+by, C(eye))
    prop(d, by)
    return d

def prop_sling(d, by, syntax=0):
    line(d, 21, 17+by, 26, 20+by, C(K6), 1)      # strap
    ell(d, 25, 20+by, 28, 23+by, C(K7))           # stone pouch
    rect(d, 26, 21+by, 27, 22+by, C(K8))
def prop_staff(d, by):
    line(d, 22, 8+by, 22, 29+by, C(K6), 1)
    ell(d, 20, 6+by, 24, 10+by, C(K9))
    px(d, 22, 7+by, C(K10))
def prop_sword(d, by):
    line(d, 23, 12+by, 23, 26+by, C(K16), 2)
    line(d, 21, 17+by, 25, 17+by, C(K9), 1)
def prop_horn(d, by):
    ell(d, 21, 14+by, 26, 18+by, C(K7))
    line(d, 25, 15+by, 29, 11+by, C(K7), 2)
    px(d, 29, 10+by, C(K9))
def prop_none(d, by): pass

WITNESS = [
    ("david", 11, 13, 6, None, prop_sling),
    ("moses", 12, 8, 6, None, prop_staff),
    ("gideon", 14, 12, 6, None, prop_horn),
    ("joshua", 15, 13, 6, None, prop_sword),
]
wits = new(32*4, 32*4)
for r,(name,skin,cloth,cloth2,metal,prop) in enumerate(WITNESS):
    for f in range(4):
        fr = new(32,32); d = ImageDraw.Draw(fr)
        bob = [0,-1,0,1][f]; leg = [0,1,0,-1][f]
        humanoid(d, bob, leg, skin, cloth, cloth2, metal, prop)
        wits.paste(outline(fr), (f*32, r*32))

# ---------------- enemies ----------------
def e_soldier(d,bob,leg,c1,c2):
    ell(d,10,28,22,31,(0,0,0,90))
    rect(d,12,22+leg,14,28,C(c2)); rect(d,17,22-leg,19,28,C(c2))
    rect(d,10,13+bob,21,22+bob,C(c2)); rect(d,11,14+bob,20,18+bob,C(c1))
    ell(d,12,7+bob,19,14+bob,C(c1)); rect(d,12,7+bob,19,9+bob,C(K3))
    px(d,14,10+bob,C(K12)); px(d,17,10+bob,C(K12))
    line(d,22,12+bob,27,4+bob,C(K5),1)       # spear
    ell(d,26,2+bob,29,5+bob,C(K6))

def e_archer(d,bob,leg,c1,c2):
    ell(d,10,28,22,31,(0,0,0,90))
    rect(d,12,22+leg,14,28,C(c2)); rect(d,17,22-leg,19,28,C(c2))
    rect(d,11,13+bob,20,22+bob,C(c2)); ell(d,12,7+bob,19,14+bob,C(c1))
    rect(d,12,6+bob,19,8+bob,C(K13))
    line(d,23,9+bob,23,23+bob,C(K6),2)       # bow
    line(d,23,9+bob,27,16+bob,C(K7),1); line(d,23,23+bob,27,16+bob,C(K7),1)
    line(d,20,16+bob,27,16+bob,C(K8),1)      # arrow

def e_raven(d,bob,leg,c1,c2):
    # wings out mid-frame
    span = [10,16,20,16][leg]
    d.polygon([(16-bob,14+bob),(16-span,8+bob),(12,16+bob)],fill=C(c2))
    d.polygon([(16+bob,14+bob),(16+span,8+bob),(20,16+bob)],fill=C(c2))
    ell(d,10,12+bob,22,22+bob,C(c1))
    ell(d,18,10+bob,24,15+bob,C(c1))         # head
    d.polygon([(23,12+bob),(28,13+bob),(23,15+bob)],fill=C(K9))  # beak

def e_beast(d,bob,leg,c1,c2):
    ell(d,8,28,24,31,(0,0,0,90))
    rect(d,9,22+bob,22,28+bob,C(c1))         # body
    rect(d,8,23+leg,11,29,C(c2)); rect(d,20,23-leg,23,29,C(c2))
    ell(d,19,15+bob,27,24+bob,C(c1))         # head
    d.polygon([(20,15+bob),(21,10+bob),(24,15+bob)],fill=C(c2))
    d.polygon([(24,15+bob),(26,10+bob),(28,15+bob)],fill=C(c2))
    px(d,24,19+bob,C(K12)); px(d,27,19+bob,C(K12))
    line(d,9,22+bob,4,16+bob,C(c2),2)        # tail

def e_scorpion(d,bob,leg,c1,c2):
    ell(d,10,28,24,31,(0,0,0,90))
    ell(d,8,18+bob,22,26+bob,C(c1))
    for k in range(3):
        line(d,10+k*4,26+bob,8+k*4,30, C(c2),1)
        line(d,14+k*4,26+bob,16+k*4,30, C(c2),1)
    ell(d,20,16+bob,27,23+bob,C(c1))         # head
    px(d,23,19+bob,C(K12)); px(d,25,19+bob,C(K12))
    line(d,10,20+bob,4,14+bob,C(c2),1)       # tail
    line(d,4,14+bob,5,8+bob,C(c2),1)
    ell(d,4,5+bob,8,9+bob,C(K12))
    line(d,26,20+bob,30,17+bob,C(c2),1)      # claw
    line(d,26,22+bob,31,22+bob,C(c2),1)

def e_giant(d,bob,leg,c1,c2,scale=1):
    ell(d,6,28,26,31,(0,0,0,100))
    rect(d,10,21+leg,14,29,C(c2)); rect(d,18,21-leg,22,29,C(c2))
    rect(d,10,12+bob,22,23+bob,C(c1))
    rect(d,10,12+bob,22,14+bob,C(c2))
    rect(d,11,22+bob,15,24+bob,C(c2)); rect(d,17,22+bob,21,24+bob,C(c2))
    ell(d,12,4+bob,21,13+bob,C(c1))
    px(d,14,7+bob,C(K12)); px(d,18,7+bob,C(K12))
    rect(d,12,9+bob,20,10+bob,C(K11))
    rect(d,6,13+bob,10,22+bob,C(c2)); rect(d,22,13+bob,26,22+bob,C(c2))
    line(d,28,10+bob,31,20+bob,C(K6),2)      # club

def e_tempter(d,bob,leg,c1,c2):
    # hooded figure with staff, purple aura
    ell(d,10,28,22,31,(0,0,0,90))
    d.polygon([(16,4+bob),(8,28),(24,28)],fill=C(c1))
    d.polygon([(16,8+bob),(11,27),(21,27)],fill=C(c2))
    ell(d,13,11+bob,19,17+bob,C(K1))
    px(d,14,13+bob,C(K9)); px(d,18,13+bob,C(K9))
    rect(d,15,17+bob,17,27+bob,C(K9))
    line(d,24,8+bob,24,29+bob,C(K6),1)
    ell(d,22,4+bob,27,9+bob,C(K17))

ENEMIES = [
    ("soldier",   lambda d,b,l: e_soldier(d,b,l,6,3)),
    ("archer",    lambda d,b,l: e_archer(d,b,l,14,13)),
    ("raven",     lambda d,b,l: e_raven(d,b,l,3,2)),
    ("beast",     lambda d,b,l: e_beast(d,b,l,11,6)),
    ("scorpion",  lambda d,b,l: e_scorpion(d,b,l,7,8)),
    ("six_finger_giant", lambda d,b,l: e_giant(d,b,l,6,11)),
    ("goliath",   lambda d,b,l: e_giant(d,b,l,5,2)),
    ("the_tempter", lambda d,b,l: e_tempter(d,b,l,18,17)),
]
ens = new(32*4, 32*len(ENEMIES))
for r,(name,fn) in enumerate(ENEMIES):
    for f in range(4):
        fr = new(32,32); d = ImageDraw.Draw(fr)
        fn(d, [0,-1,0,1][f], [0,1,0,-1][f])
        ens.paste(outline(fr),(f*32, r*32))

# ---------------- props ----------------
props = new(16*6, 16)
GEM_COLORS = [(K15,K16),(K13,K14),(K9,K10),(K17,K12)]
for i,(base,hi) in enumerate(GEM_COLORS):
    fr = new(16,16); d = ImageDraw.Draw(fr)
    d.polygon([(8,2),(14,8),(8,14),(2,8)],fill=C(base))
    d.polygon([(8,2),(11,8),(8,14),(5,8)],fill=C(hi))
    px(d,7,4,C(K10)); px(d,6,5,C(K10))
    props.paste(fr,(i*16,0))
coin = new(16,16); d = ImageDraw.Draw(coin)
ell(d,2,2,13,13,C(K7)); ell(d,3,3,12,12,C(K8)); ell(d,5,5,10,10,C(K7))
px(d,7,7,C(K10)); px(d,8,8,C(K10))
props.paste(coin,(64,0))
coal = new(16,16); d = ImageDraw.Draw(coal)
ell(d,3,3,12,12,C(K11)); ell(d,5,5,10,10,C(K19)); ell(d,6,6,9,8,C(K9))
props.paste(coal,(80,0))

# ---------------- icons ----------------
def icon_weapon(kind, a, b):
    fr = new(32,32); d = ImageDraw.Draw(fr)
    d.rounded_rectangle([1,1,30,30],radius=5,fill=C(K2),outline=C(K7))
    cx,cy = 16,17
    if kind=="sling":
        line(d,8,10,20,20,C(K6),2); ell(d,19,18,24,23,C(K6)); px(d,21,20,C(K8))
    elif kind=="staff":
        line(d,16,6,16,26,C(K6),2); ell(d,12,4,20,11,C(K9)); px(d,16,6,C(K10))
    elif kind=="torch":
        line(d,14,14,14,27,C(K6),3); ell(d,10,8,19,17,C(K19)); ell(d,13,10,17,15,C(K9))
    elif kind=="horn":
        ell(d,8,12,18,22,C(K7)); d.polygon([(17,14),(27,7),(27,11),(18,19)],fill=C(K8))
    elif kind=="censer":
        line(d,16,5,16,12,C(K7)); ell(d,9,12,23,24,C(K7)); px(d,12,17,C(K19)); px(d,19,17,C(K19))
    elif kind=="harp":
        d.polygon([(8,24),(10,7),(22,7),(24,24)],outline=C(K9),fill=None)
        for i in range(5): line(d,11+i*2,9,11+i*2,23,C(K8))
    elif kind=="olive_branch":
        line(d,9,24,22,8,C(K13),2)
        for i in range(4):
            ell(d,10+i*3,18-i*3,15+i*3,23-i*3,C(K14))
    elif kind=="jawbone":
        ell(d,8,12,20,20,C(K8)); ell(d,20,12,26,20,C(K8))
        for i in range(4): px(d,10+i*2,16,C(K1))
    elif kind=="tambourine":
        ell(d,6,7,26,27,C(K7)); ell(d,9,10,23,24,C(K11))
        for i in range(6): px(d,16+i*2-5,9,C(K9))
    elif kind=="sickle":
        d.arc([6,6,26,26],start=180,end=340,fill=C(K8),width=3); line(d,16,20,16,28,C(K6),2)
    elif kind=="spirit_blade":
        line(d,16,5,16,24,C(K16),3); line(d,10,20,22,20,C(K9),2); line(d,16,5,16,24,C(K10))
    elif kind=="menorah":
        line(d,16,10,16,26,C(K9),3)
        for dx in (-7,-4,4,7): line(d,16+dx,12,16+dx,20,C(K9),2)
        ell(d,4,10,9,14,C(K19)); ell(d,23,10,28,14,C(K19))
    elif kind=="bronze_serpent":
        line(d,12,26,12,10,C(K6),3); line(d,12,10,20,8,C(K6),3); ell(d,18,6,24,11,C(K14))
    elif kind=="chariot":
        ell(d,7,18,25,26,C(K7)); ell(d,9,20,23,24,C(K3))
        for a in (0,90,180,270):
            r=7; line(d,16,22,16+r*math.cos(math.radians(a)),22+r*math.sin(math.radians(a)),C(K8))
    elif kind=="hammer":
        line(d,15,12,15,28,C(K6),3); rect(d,8,6,22,13,C(K5)); rect(d,8,6,22,8,C(K4))
    elif kind=="scepter":
        line(d,16,12,16,28,C(K9),3); ell(d,11,5,21,14,C(K9)); px(d,15,8,C(K10))
    elif kind=="abel_blood":
        ell(d,8,10,24,26,C(K12)); ell(d,12,14,20,22,C(K11)); px(d,13,15,C(K8))
    elif kind=="voice":
        for r in (4,7,10): d.arc([16-r,16-r,16+r,16+r],start=300,end=60,fill=C(K9),width=2)
        ell(d,13,13,19,19,C(K17))
    elif kind=="fishing_net":
        for i in range(4):
            line(d,7+i*5,8,7+i*5,24,C(K8)); line(d,6,10+i*4,26,10+i*4,C(K8))
    elif kind=="heaven_keys":
        line(d,10,26,20,10,C(K9),2); ell(d,19,5,25,11,C(K9))
        line(d,14,22,20,24,C(K9),2); px(d,21,25,C(K9)); px(d,24,25,C(K9))
    else:
        ell(d,10,10,22,22,C(K9))
    return fr

WEAPONS = ["sling","staff","torch","horn","censer","harp","olive_branch","jawbone","tambourine","sickle",
           "spirit_blade","menorah","bronze_serpent","chariot","hammer","scepter","abel_blood","voice","fishing_net","heaven_keys"]
stone = [K3,K4]; cloth=[K11,K6]; metal=[K5,K3]
wi = new(32*5,32*4)
for i,w in enumerate(WEAPONS):
    fr = icon_weapon(w, stone, metal); wi.paste(fr, ((i%5)*32, (i//5)*32))

def icon_passive(pid):
    fr = new(32,32); d = ImageDraw.Draw(fr)
    d.rounded_rectangle([1,1,30,30],radius=5,fill=C(K2),outline=C(K7))
    fruits = {"love":K12,"joy":K9,"peace":K16,"patience":K13,"kindness":K19,
              "goodness":K8,"faithfulness":K10,"gentleness":K17,"self_control":K15}
    if pid in fruits:
        ell(d,8,10,24,27,C(fruits[pid])); ell(d,10,11,17,16,C(K10))
        line(d,16,10,18,5,C(K6),2); ell(d,17,4,23,9,C(K14))
    elif pid=="belt_of_truth": rect(d,6,13,26,18,C(K6)); rect(d,14,11,19,20,C(K9))
    elif pid=="breastplate": d.polygon([(8,7),(24,7),(26,24),(16,29),(6,24)],fill=C(K5)); ell(d,13,13,19,20,C(K9))
    elif pid=="gospel_shoes": rect(d,7,17,25,23,C(K6)); rect(d,7,22,25,25,C(K3)); line(d,7,17,25,17,C(K8))
    elif pid=="shield_of_faith": d.polygon([(8,6),(24,6),(24,20),(16,28),(8,20)],fill=C(K16)); line(d,16,10,16,22,C(K10),2)
    elif pid=="helmet": ell(d,8,8,24,22,C(K5)); rect(d,8,16,24,22,C(K4)); rect(d,14,10,18,26,C(K3))
    elif pid=="spirit_sword": line(d,16,5,16,22,C(K16),3); line(d,10,18,22,18,C(K9),2); rect(d,14,22,18,29,C(K6))
    elif pid=="frankincense": rect(d,10,14,22,27,C(K6)); line(d,11,12,21,12,C(K7)); 
    if pid=="frankincense":
        for (x,y) in [(13,9),(17,7),(20,10)]: ell(d,x-1,y-1,x+1,y+1,C(K8))
    elif pid=="myrrh": ell(d,8,10,24,26,C(K11)); ell(d,11,13,15,17,C(K6))
    elif pid=="olive_oil": ell(d,9,12,23,26,C(K13)); rect(d,14,4,18,13,C(K7)); px(d,16,7,C(K10))
    elif pid=="fine_linen": d.polygon([(8,6),(24,6),(26,27),(6,27)],fill=C(K10)); line(d,8,6,26,27,C(K7)); line(d,24,6,6,27,C(K7))
    elif pid=="ephod": d.polygon([(10,6),(22,6),(24,26),(8,26)],fill=C(K9)); rect(d,10,11,22,14,C(K12)); px(d,12,8,C(K16)); px(d,20,8,C(K16))
    return fr

PASSIVES = ["love","joy","peace","patience","kindness","goodness","faithfulness","gentleness","self_control",
            "belt_of_truth","breastplate","gospel_shoes","shield_of_faith","helmet","spirit_sword",
            "frankincense","myrrh","olive_oil","fine_linen","ephod"]
pi = new(32*5,32*4)
for i,p in enumerate(PASSIVES):
    pi.paste(icon_passive(p), ((i%5)*32,(i//5)*32))

# quantize to shared palette
def quant(img, path):
    pal_img = Image.new("P",(1,1))
    flat=[]
    for c in P:
        if c=="#00000000": flat += [0,0,0]
        else:
            flat += [int(c[1:3],16),int(c[3:5],16),int(c[5:7],16)]
    while len(flat)<256*3: flat += [0,0,0]
    pal_img.putpalette(flat)
    alpha = img.split()[3]
    q = img.convert("RGB").quantize(palette=pal_img, dither=Image.NONE).convert("RGBA")
    q.putalpha(alpha)
    q.save(path, optimize=True)
    return q

quant(wits, os.path.join(SPR,"witnesses.png"))
quant(ens, os.path.join(SPR,"enemies.png"))
quant(props, os.path.join(SPR,"props.png"))
quant(wi, os.path.join(ICO,"weapons.png"))
quant(pi, os.path.join(ICO,"passives.png"))
for f in ("witnesses","enemies","props"):
    im = Image.open(os.path.join(SPR,f+".png")); print(f, im.size, im.mode)
for f in ("weapons","passives"):
    im = Image.open(os.path.join(ICO,f+".png")); print(f, im.size, im.mode)
print("OK")
