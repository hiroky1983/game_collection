import unicodedata, json, sys

SMALL = {"ゃ":"や","ゅ":"ゆ","ょ":"よ","ぁ":"あ","ぃ":"い","ぅ":"う","ぇ":"え","ぉ":"お","ゎ":"わ","っ":"つ"}

def hira(s):
    return "".join(chr(ord(c)-0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in s)

def head(r): return hira(r)[0]
def tail(r):
    cs = list(hira(r))
    while cs and cs[-1] == "ー": cs.pop()
    last = cs[-1]
    return SMALL.get(last, last)
def unvoiced(c): return unicodedata.normalize("NFD", c)[0]
def accepts(h, t): return h == t or h == unvoiced(t)

# 既存 30 枚（kind, 表読み, 裏読み...）
existing = [
 ("apple","りんご"),("gorilla","ごりら"),("seaOtter","らっこ"),("koala","こあら"),("camel","らくだ"),
 ("rabbit","うさぎ"),("guitar","ぎたー"),("drum","たいこ"),("kitten","くま"),("glass","こっぷ"),
 ("squirrel","りす"),("watermelon","すいか"),("turtle","かめ"),("eyeglasses","めがね"),("cat","ねこ","にゃんこ"),
 ("spinningTop","こま"),("pillow","まふらー"),("ostrich","だちょう"),("handFan","まいく"),("crocodile","わに"),
 ("boat","ふね"),("leek","くり"),("ball","にく"),("mushroom","きのこ"),("horse","うま"),
 ("deer","しか"),("cow","うし"),("bell","すず"),("moon","つき"),("octopus","たこ"),
]
new = [
 ("うきわ","うきわ"),("かさ","かさ"),("さかな","さかな"),("なす","なす"),("きつね","きつね"),
 ("くじら","くじら"),("こおり","こおり"),("しまうま","しまうま"),("すし","すし"),("たまご","たまご"),
 ("だんご","だんご"),("にわとり","にわとり"),("たいやき","たいやき"),("まんじゅう","まんじゅう"),
 ("めだまやき","めだまやき"),("けーき","けーき"),("わたあめ","わたあめ"),("くつ","くつ"),("たけ","たけ"),("すいとう","すいとう"),
]
# 追加する裏読み（key=表読み）
alts = {
 "かめ":"うみがめ","まふらー":"すかーふ","にく":"すてーき","きのこ":"しいたけ","うし":"ぎゅう",
 "すし":"にぎり","にわとり":"こっこ","くつ":"しゅーず","きつね":"こぎつね","くま":"こぐま",
}
deck = []
for c in existing + new:
    rs = [hira(x) for x in c[1:]]
    if rs[0] in alts: rs.append(hira(alts[rs[0]]))
    deck.append((c[0], rs))

bad = 0
tails_all = [(k, tail(r)) for k, rs in deck for r in rs]
for k, rs in deck:
    for r in rs:
        if r[-1] == "ん": print("ん終わり", k, r); bad += 1
        t = tail(r)
        followers = [k2 for k2, rs2 in deck if k2 != k and any(accepts(head(x), t) for x in rs2[:1] + rs2[1:])]
        if not followers: print("受け皿なし(語尾)", k, r, t); bad += 1
    for r in rs[1:]:
        h = head(r)
        givers = [k2 for k2, t in tails_all if k2 != k and accepts(h, t)]
        if not givers: print("選ぶ契機なし(語頭)", k, r, h); bad += 1
        # 表読みでは受けられない語尾を、裏読みで新たに受けられるようになる数
        prim = head(rs[0])
        newly = sorted({t for k2, t in tails_all if k2 != k and accepts(h, t) and not accepts(prim, t)})
        print(f"{k}: {rs[0]}→{r}  新たに受けられる語尾={''.join(newly)}  裏読みの語尾 {tail(r)} の受け皿={[k2 for k2,rs2 in deck if k2!=k and any(accepts(head(x),tail(r)) for x in rs2)][:6]}")
print("NG =", bad)
# 語頭・語尾の受け皿の対応（表読みのみ）
from collections import Counter
hc = Counter(head(rs[0]) for _, rs in deck)
tc = Counter(tail(rs[0]) for _, rs in deck)
print("語頭:", dict(hc)); print("語尾:", dict(tc))
print("札数", len(deck), "裏読み付き", sum(1 for _, rs in deck if len(rs) > 1))
json.dump(deck, open(sys.argv[1] if len(sys.argv) > 1 else "/dev/null", "w"), ensure_ascii=False)
