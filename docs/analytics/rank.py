#!/usr/bin/python3
"""iTunes Search API で自社（trackId 6781719499）の検索順位を測る（#54 と同条件: country=jp, entity=software, limit=200）。"""
import json, sys, time, urllib.parse, urllib.request

TRACK = 6781719499
WORDS = sys.argv[1:] or ["将棋", "麻雀", "ポーカー", "2048", "マインスイーパー", "ブラックジャック", "大富豪",
                         "ソリティア", "ナンプレ", "詰め合わせ", "オセロ", "麻雀ソリティア", "あそびば",
                         "中断", "詰め合せ", "一人遊び", "卓上", "機内", "フリーセル", "花札", "囲碁", "チェス"]

def measure(word):
    q = urllib.parse.urlencode({"country": "jp", "entity": "software", "limit": 200, "term": word, "cb": int(time.time() * 1000)})
    with urllib.request.urlopen("https://itunes.apple.com/search?" + q, timeout=30) as r:
        res = json.load(r)["results"]
    rank = next((i + 1 for i, a in enumerate(res) if a.get("trackId") == TRACK), None)
    title_hits = sum(1 for a in res if word.lower() in a.get("trackName", "").lower())
    top5 = sorted((a.get("userRatingCount", 0) for a in res[:5]))
    median = top5[len(top5) // 2] if top5 else 0
    return rank, len(res), title_hits, median

print("語\t順位\t件数\tタイトル一致\t上位5評価数中央値")
for w in WORDS:
    try:
        rank, n, hits, med = measure(w)
        print(f"{w}\t{rank if rank else '圏外'}\t{n}\t{hits}\t{med}")
    except Exception as e:
        print(f"{w}\tERR {e}")
    time.sleep(1.2)
