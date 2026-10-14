#!/usr/bin/env python3
"""ASO・GA4 の日次の数字を取って保存し、Google スプレッドシートに出す（Issue #2231・#2238）。

なぜ要るか: App Analytics（Analytics Reports API）の日次インスタンスは数日分しか保持されないため、
毎日取ってローカルに貯めないと v1.1.11 以降の推移が追えない。GA4・広告収益も同じ表で追う。

やること（launchd から毎日 1 回。仕組みと入れ方・止め方は docs/ai-devops.md「ASO の日次取得」）:
  1. GA4（#2238）: サービスアカウントの鍵で GA4 Data API を読み、アクティブユーザー（App Store 版の絞り込みあり・なし・
     日本／日本以外）・新規（first_open）・セッション・game_open / game_start / game_end / reward_offer /
     reward_request / reward_ad / share_tap（全体とゲーム別）・広告収益（AdMob リンク経由）を
     ~/asobiba-kpi/ga4/daily.csv に保存する。直近は毎回取り直して上書き
  2. ASC: 既存の ONGOING リクエスト（REQUEST_ID）から「App Store Discovery and Engagement Standard」
     「App Downloads Standard」の DAILY インスタンスを一覧し、まだ保存していない processingDate の分を
     ~/asobiba-kpi/aso/raw/<種類>/<processingDate>.tsv に保存する（Mac が止まっていた日の分も、
     API に残っている範囲で次回に取り戻す）
  3. raw/ の全ファイルから daily.csv を作り直す。1 つの日付は複数のインスタンスに重複して入るため、
     その日付を含むファイルのうち processingDate が最も新しいものだけを使う（= 重複排除）。
     raw/ に無くなった日付は既存の daily.csv の行を残す
  4. スプレッドシート（SHEET_ID）の日次タブ・週次まとめを丸ごと書き直す（同じ日付は上書き・新しい日は追記）。
     GA4・ASC のどちらかが失敗しても残りは続け、週次まとめの先頭に「取得失敗: 日時・どの取得か」を出す

ASC の API は GET だけを使う（GA4 の runReport は読み取りの POST）。リクエストが無い・止まっている場合は作り直さずにエラー終了する
（作成は会長の判断を経て手で行う）。鍵・トークン・署名付き URL はログにも CSV にも出さない。

テスト: bash Scripts/tests/test-aso-daily.sh
"""
import argparse
import base64
import csv
import datetime
import glob
import gzip
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

REQUEST_ID = "7e25e0eb-cb38-4e08-b230-981d472bb098"
API = "https://api.appstoreconnect.apple.com"
KEY_JSON = os.path.expanduser("~/.appstoreconnect/asc-key.json")

# raw/ の下のディレクトリ名 → レポート名
REPORTS = {
    "engagement": "App Store Discovery and Engagement Standard",
    "downloads": "App Downloads Standard",
}

JST = datetime.timezone(datetime.timedelta(hours=9))
# 比較の基準。基準値は v1.1.11 公開前（v1.1.8 公開〜）の 10/3〜10/11、v1.1.11 は 10/12 公開
BASELINE_START = datetime.date(2026, 10, 3)
BASELINE_END = datetime.date(2026, 10, 11)
V1111_START = datetime.date(2026, 10, 12)

# 流入元（Source Type）→ 列名の接尾辞
SOURCES = {
    "App Store search": "search",
    "App Store browse": "browse",
    "Web referrer": "web",
    "App referrer": "app",
}

ENGAGEMENT_COLS = [
    "impr_total", "impr_unique", "impr_total_jp", "impr_total_other", "impr_unique_jp", "impr_unique_other",
    "impr_search", "impr_browse", "impr_web", "impr_app",
    "pv_total", "pv_unique", "pv_total_jp", "pv_total_other", "pv_unique_jp", "pv_unique_other",
    "pv_search", "pv_browse", "pv_web", "pv_app",
]
DOWNLOADS_COLS = [
    "dl_first_total", "dl_first_jp", "dl_first_other",
    "dl_first_search", "dl_first_browse", "dl_first_web", "dl_first_app",
    "dl_redownload_total", "dl_redownload_jp", "dl_redownload_other",
]
RATE_COLS = ["press_rate_pct", "install_rate_pct"]
META_COLS = ["engagement_processing_date", "downloads_processing_date"]
FIELDNAMES = ["date"] + ENGAGEMENT_COLS + DOWNLOADS_COLS + RATE_COLS + META_COLS


def log(msg):
    now = datetime.datetime.now(JST).strftime("%Y-%m-%d %H:%M:%S")
    print("[aso-daily %s] %s" % (now, msg), flush=True)


# ---------------------------------------------------------------- 集計（API に依存しない部分）

def read_tsv(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def to_int(v):
    try:
        return int(v or 0)
    except ValueError:
        return 0


def pick_latest(files):
    """files: [(processing_date, rows)]。日付ごとに、その日付を含むファイルのうち processingDate が
    最も新しいものの行だけを返す。戻り値: {date: (processing_date, rows)}"""
    best = {}
    for pdate, rows in sorted(files, key=lambda x: x[0]):
        by_date = {}
        for r in rows:
            d = r.get("Date")
            if d:
                by_date.setdefault(d, []).append(r)
        for d, rs in by_date.items():
            best[d] = (pdate, rs)  # 昇順に回すので後勝ち = 最新の processingDate
    return best


def aggregate_engagement(rows):
    a = dict.fromkeys(ENGAGEMENT_COLS, 0)
    for r in rows:
        ev, page = r.get("Event"), r.get("Page Type")
        if ev == "Impression":
            p = "impr"
        elif ev == "Page view" and page == "Product page":
            p = "pv"
        else:
            continue
        c, u = to_int(r.get("Counts")), to_int(r.get("Unique Counts"))
        tg = "jp" if r.get("Territory") == "JP" else "other"
        a[p + "_total"] += c
        a[p + "_unique"] += u
        a["%s_total_%s" % (p, tg)] += c
        a["%s_unique_%s" % (p, tg)] += u
        s = SOURCES.get(r.get("Source Type"))
        if s:
            a["%s_%s" % (p, s)] += c
    return a


def aggregate_downloads(rows):
    a = dict.fromkeys(DOWNLOADS_COLS, 0)
    for r in rows:
        t = r.get("Download Type")
        if t == "First-time download":
            p = "dl_first"
        elif t == "Redownload":
            p = "dl_redownload"
        else:
            continue
        c = to_int(r.get("Counts"))
        tg = "jp" if r.get("Territory") == "JP" else "other"
        a[p + "_total"] += c
        a["%s_%s" % (p, tg)] += c
        s = SOURCES.get(r.get("Source Type"))
        if s and p == "dl_first":
            a["dl_first_" + s] += c
    return a


def load_raw(raw_dir, kind):
    files = []
    for fp in sorted(glob.glob(os.path.join(raw_dir, kind, "*.tsv"))):
        pdate = os.path.splitext(os.path.basename(fp))[0]
        files.append((pdate, read_tsv(fp)))
    return files


def rates(row):
    impr, pv, dl = to_int(row.get("impr_total")), to_int(row.get("pv_total")), to_int(row.get("dl_first_total"))
    has_e = row.get("impr_total", "") != ""
    has_d = row.get("dl_first_total", "") != ""
    row["press_rate_pct"] = round(pv / impr * 100, 2) if has_e and impr else ""
    row["install_rate_pct"] = round(dl / pv * 100, 2) if has_e and has_d and pv else ""


def build_daily(raw_dir, existing):
    """raw/ から日次の行を作り、既存の行（{date: row}）に重ねる。raw に無い日付・種類は既存のまま残す。"""
    rows = {d: dict(r) for d, r in existing.items()}
    for kind, cols, agg in (("engagement", ENGAGEMENT_COLS, aggregate_engagement),
                            ("downloads", DOWNLOADS_COLS, aggregate_downloads)):
        for d, (pdate, rs) in pick_latest(load_raw(raw_dir, kind)).items():
            row = rows.setdefault(d, {"date": d})
            row.update(agg(rs))
            row[kind + "_processing_date"] = pdate
    out = []
    for d in sorted(rows):
        row = {k: rows[d].get(k, "") for k in FIELDNAMES}
        row["date"] = d
        rates(row)
        out.append(row)
    return out


def read_daily(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8", newline="") as f:
        return {r["date"]: r for r in csv.DictReader(f) if r.get("date")}


def write_atomic(path, write_fn, mode="w"):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-")
    try:
        with os.fdopen(fd, mode, **({"encoding": "utf-8", "newline": ""} if "b" not in mode else {})) as f:
            write_fn(f)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def write_daily(path, rows):
    def w(f):
        cw = csv.DictWriter(f, fieldnames=FIELDNAMES)
        cw.writeheader()
        cw.writerows(rows)
    write_atomic(path, w)


# ---------------------------------------------------------------- 期間の集計

def _has(row, kind):
    if "e" in kind and row.get("impr_total", "") == "":
        return False
    if "d" in kind and row.get("dl_first_total", "") == "":
        return False
    return True


def period_value(rows, start, end, num, den, kind):
    """start〜end（両端含む）の 1 日平均（den 無し）または合計の比 %（den あり）。データの無い日は除く。
    戻り値: (値 or None, データのある日数)"""
    sel = [r for r in rows if start.isoformat() <= r["date"] <= end.isoformat() and _has(r, kind)]
    if not sel:
        return None, 0
    n = sum(to_int(r.get(num)) for r in sel)
    if den is None:
        return n / len(sel), len(sel)
    d = sum(to_int(r.get(den)) for r in sel)
    return (n / d * 100 if d else None), len(sel)


# ---------------------------------------------------------------- App Store Connect（GET のみ）

class AscError(Exception):
    pass


def _b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=")


def make_jwt():
    with open(KEY_JSON, encoding="utf-8") as f:
        cfg = json.load(f)
    head = _b64(json.dumps({"alg": "ES256", "kid": cfg["key_id"], "typ": "JWT"}).encode())
    now = int(time.time())
    payload = _b64(json.dumps({"iss": cfg["issuer_id"], "iat": now, "exp": now + 600,
                               "aud": "appstoreconnect-v1"}).encode())
    msg = head + b"." + payload
    keyfile = os.path.expanduser("~/.appstoreconnect/AuthKey_%s.p8" % cfg["key_id"])
    tmpkey = None
    try:
        if not os.path.exists(keyfile):
            fd, tmpkey = tempfile.mkstemp(prefix="asc-", suffix=".p8")
            with os.fdopen(fd, "w") as f:
                f.write(cfg["key"])
            keyfile = tmpkey
        p = subprocess.run(["openssl", "dgst", "-sha256", "-sign", keyfile], input=msg,
                           capture_output=True, timeout=30)
    finally:
        if tmpkey:
            os.unlink(tmpkey)
    if p.returncode != 0:
        raise AscError("JWT の署名に失敗しました（openssl 終了コード %d）" % p.returncode)
    der = p.stdout
    # DER の ECDSA 署名 (r, s) を JWS の 64 バイト固定長へ
    i = 2 if der[1] < 0x80 else 3
    rl = der[i + 1]
    r = der[i + 2:i + 2 + rl]
    j = i + 2 + rl
    sl = der[j + 1]
    s = der[j + 2:j + 2 + sl]
    raw = r.lstrip(b"\0").rjust(32, b"\0") + s.lstrip(b"\0").rjust(32, b"\0")
    return (msg + b"." + _b64(raw)).decode()


class Asc:
    def __init__(self):
        self._token, self._exp = None, 0

    def _auth(self):
        if time.time() > self._exp - 60:
            self._token, self._exp = make_jwt(), time.time() + 600
        return self._token

    def get(self, path, params=None):
        url = path if path.startswith("http") else API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={"Authorization": "Bearer " + self._auth(),
                                                   "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            # URL・ヘッダは出さない。エラーの見出しだけ
            detail = ""
            try:
                errs = json.loads(e.read()).get("errors") or []
                detail = "; ".join("%s: %s" % (x.get("title", ""), x.get("detail", "")) for x in errs)[:300]
            except Exception:
                pass
            raise AscError("ASC API が HTTP %d を返しました（%s）%s" % (e.code, urllib.parse.urlparse(url).path, detail))

    def get_all(self, path, params=None):
        data, nxt = [], None
        page = self.get(path, params)
        while True:
            data += page.get("data") or []
            nxt = (page.get("links") or {}).get("next")
            if not nxt:
                return data
            page = self.get(nxt)


def download_segment(url):
    """署名付き URL から取得して展開した bytes を返す。URL はどこにも出さない。"""
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=120) as resp:
            b = resp.read()
    except urllib.error.HTTPError as e:
        raise AscError("セグメントの取得が HTTP %d で失敗しました" % e.code)
    except urllib.error.URLError:
        raise AscError("セグメントの取得に失敗しました（接続エラー）")
    try:
        return gzip.decompress(b)
    except OSError:
        return b


def join_segments(chunks):
    """複数セグメントの TSV を 1 本にする（2 本目以降のヘッダ行は落とす）。"""
    out, header = [], None
    for c in chunks:
        lines = c.decode("utf-8").splitlines()
        if not lines:
            continue
        if header is None:
            header = lines[0]
            out.append(header)
        out += [ln for ln in lines[1:] if ln != header]
    return ("\n".join(out) + "\n").encode("utf-8") if out else b""


def fetch(raw_dir):
    asc = Asc()
    req = asc.get("/v1/analyticsReportRequests/" + REQUEST_ID).get("data") or {}
    attrs = req.get("attributes") or {}
    if attrs.get("accessType") != "ONGOING" or attrs.get("stoppedDueToInactivity"):
        raise AscError("リクエスト %s が ONGOING で動いていません（accessType=%s, stoppedDueToInactivity=%s）。"
                       "作り直しは会長判断のため自動では行いません" % (REQUEST_ID, attrs.get("accessType"),
                                                                attrs.get("stoppedDueToInactivity")))
    saved = 0
    for kind, name in REPORTS.items():
        reports = asc.get_all("/v1/analyticsReportRequests/%s/reports" % REQUEST_ID, {"filter[name]": name})
        reports = [r for r in reports if (r.get("attributes") or {}).get("name") == name]
        if not reports:
            raise AscError("レポート「%s」がリクエストにありません" % name)
        instances = asc.get_all("/v1/analyticsReports/%s/instances" % reports[0]["id"],
                                {"filter[granularity]": "DAILY", "limit": "200"})
        avail = sorted((i["attributes"]["processingDate"], i["id"]) for i in instances)
        new = 0
        for pdate, iid in avail:
            dest = os.path.join(raw_dir, kind, pdate + ".tsv")
            if os.path.exists(dest):
                continue
            segs = asc.get_all("/v1/analyticsReportInstances/%s/segments" % iid)
            data = join_segments([download_segment(s["attributes"]["url"]) for s in segs])
            if not data:
                log("%s: processingDate %s は空のため保存しない" % (kind, pdate))
                continue
            write_atomic(dest, lambda f: f.write(data), mode="wb")
            new += 1
        log("%s: API 上のインスタンス %d 件（%s〜%s）、新規保存 %d 件" % (
            kind, len(avail), avail[0][0] if avail else "-", avail[-1][0] if avail else "-", new))
        saved += new
    return saved


# ---------------------------------------------------------------- GA4（#2238）
#
# GA4 Data API（runReport）から日次の数字を取り、~/asobiba-kpi/ga4/daily.csv に縦持ち
# （date, metric, game_id, ad_unit, value。game_id・ad_unit が空 = 全体）で保存する。GA4 は直近数日の数字が後から
# 変わるため、毎回「最後に取った日の 2 日前〜昨日」を取り直し、取れた日付の行は丸ごと置き換える。
# App Store 版だけに絞る（ユーザープロパティ build_channel = appstore）。ただし first_open は
# build_channel が付く前に送られるため絞れず、新規（new_users）は全ビルドの first_open の件数。
# 広告収益（AdMob を GA4 にリンク・2026-10-15〜）も全ビルドで取る（開発版・TestFlight はテスト広告で収益 0）。
# 通貨はプロパティの通貨（USD）。リンク前の日は 0 で返るため、週次では表示回数 0 の日を「データなし」とする。

GA4_PROPERTY = "549325996"
GA4_KEY = os.path.expanduser("~/asobiba-secrets/asobiba-510718-c05fe74afc23.json")
GA4_API = "https://analyticsdata.googleapis.com/v1beta/properties/%s:runReport" % GA4_PROPERTY
GA4_BACKFILL_START = datetime.date(2026, 8, 1)  # daily.csv が空のときに遡る日（GA4 のデータは 2026-08-10 から）
GA4_REFETCH_DAYS = 3  # 直近は数字が変わるので毎回取り直す日数（昨日を含む）
GA4_EVENTS = ["game_open", "game_start", "game_end", "reward_offer", "reward_request", "reward_ad", "share_tap"]
GA4_FIELDNAMES = ["date", "metric", "game_id", "ad_unit", "value"]
GA4_AD_METRICS = {"totalAdRevenue": "ad_revenue", "publisherAdImpressions": "ad_impressions",
                  "publisherAdClicks": "ad_clicks"}
APPSTORE_FILTER = {"filter": {"fieldName": "customUser:build_channel", "stringFilter": {"value": "appstore"}}}
# 週次で推移を見るゲーム（v1.1.12 の新ゲーム 2 本と柵越えおじさん）
GA4_WATCH_GAMES = ["ojisanpuzzle", "anzan", "homerun"]
# 週次コメントの表示名（無い ID は ID のまま出す）
GAME_NAMES = {
    "2048": "2048", "anzan": "ぱっと暗算", "backgammon": "バックギャモン", "blackjack": "ブラックジャック",
    "blocks": "ブロック崩し", "chess": "チェス", "colorrelay": "いろリレー", "concentration": "神経衰弱",
    "daifugo": "大富豪", "fifteen": "15パズル", "freecell": "フリーセル", "fruits": "くっつきフルーツ",
    "go": "囲碁", "gomoku": "五目並べ", "hanafuda": "花札こいこい", "homerun": "柵越えおじさん",
    "mahjong": "麻雀ソリティア", "mahjong4": "麻雀", "minesweeper": "マインスイーパー",
    "ojisanpuzzle": "おじさんの荷物運びパズル", "othello": "オセロ", "poker": "ポーカー",
    "roulette": "ルーレット", "runner": "チャリンコおじさん", "shiritori": "カードしりとり", "shogi": "将棋",
    "solitaire": "ソリティア", "speed": "スピード", "spider": "スパイダーソリティア", "sudoku": "ナンプレ",
}


class Ga4Error(Exception):
    pass


def ga4_queries(start, end):
    """取得する runReport の本文。キーは保存時の解釈に使う名前（ga4_rows_from_reports と対）。"""
    dr = [{"startDate": start.isoformat(), "endDate": end.isoformat()}]
    events = {"filter": {"fieldName": "eventName", "inListFilter": {"values": GA4_EVENTS}}}
    ev_metrics = [{"name": "eventCount"}, {"name": "totalUsers"}]
    return {
        "active": {"dateRanges": dr, "dimensions": [{"name": "date"}],
                   "metrics": [{"name": "activeUsers"}, {"name": "sessions"}], "dimensionFilter": APPSTORE_FILTER},
        "active_all": {"dateRanges": dr, "dimensions": [{"name": "date"}],
                       "metrics": [{"name": "activeUsers"}, {"name": "sessions"}]},
        "active_country": {"dateRanges": dr, "dimensions": [{"name": "date"}, {"name": "countryId"}],
                           "metrics": [{"name": "activeUsers"}], "dimensionFilter": APPSTORE_FILTER},
        "events": {"dateRanges": dr, "dimensions": [{"name": "date"}, {"name": "eventName"}],
                   "metrics": ev_metrics,
                   "dimensionFilter": {"andGroup": {"expressions": [APPSTORE_FILTER, events]}}},
        "events_by_game": {"dateRanges": dr,
                           "dimensions": [{"name": "date"}, {"name": "eventName"}, {"name": "customEvent:game_id"}],
                           "metrics": ev_metrics,
                           "dimensionFilter": {"andGroup": {"expressions": [APPSTORE_FILTER, events]}}},
        "first_open": {"dateRanges": dr, "dimensions": [{"name": "date"}], "metrics": [{"name": "eventCount"}],
                       "dimensionFilter": {"filter": {"fieldName": "eventName",
                                                      "stringFilter": {"value": "first_open"}}}},
        "ads": {"dateRanges": dr, "dimensions": [{"name": "date"}],
                "metrics": [{"name": m} for m in GA4_AD_METRICS]},
        "ads_by_unit": {"dateRanges": dr,
                        "dimensions": [{"name": "date"}, {"name": "adFormat"}, {"name": "adUnitName"}],
                        "metrics": [{"name": m} for m in GA4_AD_METRICS]},
    }


def ga4_report_rows(resp):
    """runReport の応答を [{次元名/指標名: 値}] にする。"""
    dh = [h["name"] for h in resp.get("dimensionHeaders") or []]
    mh = [h["name"] for h in resp.get("metricHeaders") or []]
    out = []
    for r in resp.get("rows") or []:
        d = dict(zip(dh, [v.get("value", "") for v in r.get("dimensionValues") or []]))
        d.update(zip(mh, [v.get("value", "") for v in r.get("metricValues") or []]))
        out.append(d)
    return out


def _ga4_date(s):
    return "%s-%s-%s" % (s[0:4], s[4:6], s[6:8]) if len(s) == 8 and s.isdigit() else None


def _to_float(v):
    try:
        return float(v or 0)
    except ValueError:
        return 0.0


def ga4_rows_from_reports(reports):
    """{ga4_queries のキー: runReport の応答} → 縦持ちの行。
    応答に無いキーは飛ばす。game_id の無い（(not set)・空）イベントはゲーム別には入れない（全体には入る）。
    広告の内訳は ad_unit 列に「広告フォーマット/広告ユニット名」で入れる。"""
    out = []

    def add(date, metric, game, value, unit=""):
        d = _ga4_date(date or "")
        if d:
            v = ("%.6f" % _to_float(value)).rstrip("0").rstrip(".") if metric == "ad_revenue" else str(to_int(value))
            out.append({"date": d, "metric": metric, "game_id": game, "ad_unit": unit, "value": v})

    for r in ga4_report_rows(reports.get("active") or {}):
        add(r.get("date"), "active_users", "", r.get("activeUsers"))
        add(r.get("date"), "sessions", "", r.get("sessions"))
    for r in ga4_report_rows(reports.get("active_all") or {}):
        add(r.get("date"), "active_users_all", "", r.get("activeUsers"))
        add(r.get("date"), "sessions_all", "", r.get("sessions"))
    country = {}
    for r in ga4_report_rows(reports.get("active_country") or {}):
        k = (r.get("date"), "active_users_jp" if r.get("countryId") == "JP" else "active_users_other")
        country[k] = country.get(k, 0) + to_int(r.get("activeUsers"))
    for d in set(d for d, _ in country):  # 片方しか無い日は 0 を入れる（平均から抜けないように）
        country.setdefault((d, "active_users_jp"), 0)
        country.setdefault((d, "active_users_other"), 0)
    for (d, m), v in sorted(country.items()):
        add(d, m, "", v)
    for r in ga4_report_rows(reports.get("first_open") or {}):
        add(r.get("date"), "new_users", "", r.get("eventCount"))
    for r in ga4_report_rows(reports.get("events") or {}):
        ev = r.get("eventName")
        if ev in GA4_EVENTS:
            add(r.get("date"), ev + "_count", "", r.get("eventCount"))
            add(r.get("date"), ev + "_users", "", r.get("totalUsers"))
    for r in ga4_report_rows(reports.get("events_by_game") or {}):
        ev, g = r.get("eventName"), (r.get("customEvent:game_id") or "").strip()
        if ev in GA4_EVENTS and g and g != "(not set)":
            add(r.get("date"), ev + "_count", g, r.get("eventCount"))
            add(r.get("date"), ev + "_users", g, r.get("totalUsers"))
    for r in ga4_report_rows(reports.get("ads") or {}):
        for m, name in GA4_AD_METRICS.items():
            add(r.get("date"), name, "", r.get(m))
    for r in ga4_report_rows(reports.get("ads_by_unit") or {}):
        unit = "%s/%s" % (r.get("adFormat") or "(not set)", r.get("adUnitName") or "(not set)")
        for m, name in GA4_AD_METRICS.items():
            add(r.get("date"), name, "", r.get(m), unit)
    return out


def read_ga4_daily(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", newline="") as f:
        return [r for r in csv.DictReader(f) if r.get("date")]


def merge_ga4(existing, new):
    """new に出てくる日付は既存の行を丸ごと捨てて new に置き換える（取り直し＝上書き。消えたゲームの行も残さない）。
    new に無い日付の既存行はそのまま。同じ (date, metric, game_id) は 1 行にする。"""
    fresh = set(r["date"] for r in new)
    keyed = {}
    for r in [r for r in existing if r["date"] not in fresh] + new:
        keyed[(r["date"], r["metric"], r.get("game_id", ""), r.get("ad_unit", ""))] = {
            k: r.get(k, "") for k in GA4_FIELDNAMES}
    return [keyed[k] for k in sorted(keyed)]


def write_ga4_daily(path, rows):
    def w(f):
        cw = csv.DictWriter(f, fieldnames=GA4_FIELDNAMES)
        cw.writeheader()
        cw.writerows(rows)
    write_atomic(path, w)


def ga4_fetch_range(existing, today):
    """(start, end)。end = 昨日。既存の最終日の (GA4_REFETCH_DAYS-1) 日前から、ただし昨日から数えて
    GA4_REFETCH_DAYS 日は必ず含める。既存が空なら GA4_BACKFILL_START から。"""
    end = today - datetime.timedelta(days=1)
    start = end - datetime.timedelta(days=GA4_REFETCH_DAYS - 1)
    if existing:
        last = parse_date(max(r["date"] for r in existing))
        start = min(start, last - datetime.timedelta(days=GA4_REFETCH_DAYS - 1))
    else:
        start = GA4_BACKFILL_START
    return start, end


GA4_SCOPE = "https://www.googleapis.com/auth/analytics.readonly"
SHEETS_SCOPE = "https://www.googleapis.com/auth/spreadsheets"


def google_token(scope):
    """サービスアカウントの鍵から JWT（RS256・openssl で署名）を作り、アクセストークンに替える。
    鍵・JWT・トークンはどこにも出さない。"""
    try:
        with open(GA4_KEY, encoding="utf-8") as f:
            k = json.load(f)
    except FileNotFoundError:
        raise Ga4Error("サービスアカウントの鍵ファイルがありません（%s）" % GA4_KEY)
    except (OSError, ValueError):
        raise Ga4Error("サービスアカウントの鍵ファイルを読めません（%s）" % GA4_KEY)
    now = int(time.time())
    head = _b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claim = _b64(json.dumps({"iss": k.get("client_email", ""),
                             "scope": scope,
                             "aud": "https://oauth2.googleapis.com/token", "iat": now, "exp": now + 3600}).encode())
    msg = head + b"." + claim
    fd, tmpkey = tempfile.mkstemp(prefix="ga4-", suffix=".pem")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(k.get("private_key", ""))
        p = subprocess.run(["openssl", "dgst", "-sha256", "-sign", tmpkey], input=msg,
                           capture_output=True, timeout=30)
    finally:
        os.unlink(tmpkey)
    if p.returncode != 0:
        raise Ga4Error("JWT の署名に失敗しました（openssl 終了コード %d）" % p.returncode)
    data = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                                   "assertion": (msg + b"." + _b64(p.stdout)).decode()}).encode()
    try:
        with urllib.request.urlopen("https://oauth2.googleapis.com/token", data, timeout=60) as resp:
            tok = json.loads(resp.read()).get("access_token")
    except urllib.error.HTTPError as e:
        reason = ""
        try:
            reason = str(json.loads(e.read()).get("error", ""))[:80]
        except Exception:
            pass
        raise Ga4Error("認証に失敗しました（トークン発行が HTTP %d %s）。鍵の失効・削除を疑う" % (e.code, reason))
    except urllib.error.URLError:
        raise Ga4Error("認証に失敗しました（トークン発行に接続できない）")
    if not tok:
        raise Ga4Error("認証に失敗しました（トークンが返らなかった）")
    return tok


def ga4_run(tok, body):
    rows, offset, first = [], 0, None
    while True:
        b = dict(body, limit=10000, offset=offset)
        req = urllib.request.Request(GA4_API, data=json.dumps(b).encode(),
                                     headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                r = json.loads(resp.read())
        except urllib.error.HTTPError as e:
            msg = ""
            try:
                msg = (json.loads(e.read()).get("error") or {}).get("message", "")[:200]
            except Exception:
                pass
            hint = "（閲覧者の権限が外れた可能性）" if e.code in (401, 403) else ""
            raise Ga4Error("GA4 API が HTTP %d を返しました%s %s" % (e.code, hint, msg))
        except urllib.error.URLError:
            raise Ga4Error("GA4 API に接続できませんでした")
        if first is None:
            first = r
        rows += r.get("rows") or []
        offset += len(r.get("rows") or [])
        if not r.get("rows") or offset >= int(r.get("rowCount") or 0):
            break
    first["rows"] = rows
    return first


def fetch_ga4(existing, today):
    start, end = ga4_fetch_range(existing, today)
    tok = google_token(GA4_SCOPE)
    reports = {name: ga4_run(tok, body) for name, body in ga4_queries(start, end).items()}
    new = ga4_rows_from_reports(reports)
    if not new:
        raise Ga4Error("%s〜%s の行が 1 件も返りませんでした（絞り込み build_channel=appstore の不調を疑う）"
                       % (start, end))
    days = sorted(set(r["date"] for r in new))
    log("GA4: %s〜%s を取得、%d 行（%s〜%s の %d 日分）" % (start, end, len(new), days[0], days[-1], len(days)))
    return new


def _ga4_sum(rows, metric, game, start, end, unit="", days=None):
    """期間の合計と、その指標の行がある日数。days を渡すとその日付（ISO）だけを数える。"""
    vals = {}
    for r in rows:
        if (r["metric"] == metric and r.get("game_id", "") == game and r.get("ad_unit", "") == unit
                and start.isoformat() <= r["date"] <= end.isoformat() and (days is None or r["date"] in days)):
            vals[r["date"]] = _to_float(r["value"]) if metric == "ad_revenue" else to_int(r["value"])
    return sum(vals.values()), len(vals)


def _ad_days(rows, start, end):
    """広告のデータがある日（全体の表示回数が 0 より大きい日）。AdMob リンク前の 0 の日を除くため。"""
    return set(r["date"] for r in rows if r["metric"] == "ad_impressions" and not r.get("game_id")
               and not r.get("ad_unit") and start.isoformat() <= r["date"] <= end.isoformat()
               and to_int(r["value"]) > 0)


# ---------------------------------------------------------------- Google スプレッドシート（#2238）
#
# 毎回 daily.csv（ASO・GA4）から各タブの中身を作り直して丸ごと書き込む（= 新しい日は追記・同じ日付は上書き）。
# 初回は ASO の既存データ（~/asobiba-kpi/aso/daily.csv）もそのまま入る。
# 「週次まとめ」の先頭に最終更新と取得の成否（失敗したら「取得失敗: 日時・どの取得か」）を出す。

SHEET_ID = "1FSwmBy81utUvmt8z2b0eo6kGQ8jgXFhZgDoj_rhuVU4"  # 「あそびば KPI（毎日の数字）」
SHEETS_API = "https://sheets.googleapis.com/v4/spreadsheets/" + SHEET_ID
TAB_WEEKLY, TAB_ASO, TAB_GA4, TAB_GAMES, TAB_ADS = "週次まとめ", "ASO（日次）", "GA4（日次）", "ゲーム別（日次）", "広告（日次）"
TABS = [TAB_WEEKLY, TAB_ASO, TAB_GA4, TAB_GAMES, TAB_ADS]
DEFAULT_SHEET_TITLES = ("シート1", "Sheet1")
WEEKLY_TABLE_ROW = 47  # 週次の表の見出し行（1 始まり）。上は状態の行とグラフ 4 本の置き場
CHART_ROWS = 5000  # グラフが参照する行数（日次の行が増えても描かれるよう広めに取る）

ASO_HEADERS = {
    "date": "日付", "impr_total": "インプレッション", "impr_unique": "インプレッション（ユニーク）",
    "impr_total_jp": "インプレッション（日本）", "impr_total_other": "インプレッション（日本以外）",
    "impr_unique_jp": "ユニーク（日本）", "impr_unique_other": "ユニーク（日本以外）",
    "impr_search": "インプレッション（検索）", "impr_browse": "インプレッション（ブラウズ）",
    "impr_web": "インプレッション（Web 参照）", "impr_app": "インプレッション（アプリ参照）",
    "pv_total": "閲覧", "pv_unique": "閲覧（ユニーク）", "pv_total_jp": "閲覧（日本）", "pv_total_other": "閲覧（日本以外）",
    "pv_unique_jp": "閲覧ユニーク（日本）", "pv_unique_other": "閲覧ユニーク（日本以外）",
    "pv_search": "閲覧（検索）", "pv_browse": "閲覧（ブラウズ）", "pv_web": "閲覧（Web 参照）", "pv_app": "閲覧（アプリ参照）",
    "dl_first_total": "初回 DL", "dl_first_jp": "初回 DL（日本）", "dl_first_other": "初回 DL（日本以外）",
    "dl_first_search": "初回 DL（検索）", "dl_first_browse": "初回 DL（ブラウズ）", "dl_first_web": "初回 DL（Web 参照）",
    "dl_first_app": "初回 DL（アプリ参照）", "dl_redownload_total": "再 DL", "dl_redownload_jp": "再 DL（日本）",
    "dl_redownload_other": "再 DL（日本以外）", "press_rate_pct": "押される割合 %", "install_rate_pct": "入れる割合 %",
    "engagement_processing_date": "使った版（インプレッション系）", "downloads_processing_date": "使った版（DL 系）",
}
# GA4（日次）の列: (見出し, 指標名)。game_id・ad_unit が空の「全体」の行から取る
GA4_DAILY_COLS = [
    ("アクティブユーザー（App Store 版）", "active_users"), ("アクティブユーザー（全ビルド）", "active_users_all"),
    ("アクティブ 日本（App Store 版）", "active_users_jp"), ("アクティブ 日本以外（App Store 版）", "active_users_other"),
    ("新規（first_open・全ビルド）", "new_users"),
    ("セッション（App Store 版）", "sessions"), ("セッション（全ビルド）", "sessions_all"),
    ("ゲームを開いた（game_open）", "game_open_count"), ("開いた人数", "game_open_users"),
    ("プレイ開始（game_start）", "game_start_count"), ("プレイした人数", "game_start_users"),
    ("プレイ終了（game_end）", "game_end_count"), ("終えた人数", "game_end_users"),
    ("広告の提示（reward_offer）", "reward_offer_count"), ("提示した人数", "reward_offer_users"),
    ("広告の要求（reward_request）", "reward_request_count"), ("要求した人数", "reward_request_users"),
    ("広告の視聴完了（reward_ad）", "reward_ad_count"), ("視聴した人数", "reward_ad_users"),
    ("共有ボタン（share_tap）", "share_tap_count"), ("共有した人数", "share_tap_users"),
    ("広告収益 USD（全ビルド）", "ad_revenue"), ("広告の表示回数", "ad_impressions"), ("広告のクリック", "ad_clicks"),
]
GAME_DAILY_COLS = [
    ("開いた（game_open）", "game_open_count"), ("開いた人数", "game_open_users"),
    ("プレイ開始（game_start）", "game_start_count"), ("プレイした人数", "game_start_users"),
    ("プレイ終了（game_end）", "game_end_count"), ("終えた人数", "game_end_users"),
    ("広告の提示", "reward_offer_count"), ("広告の要求", "reward_request_count"),
    ("広告の視聴完了", "reward_ad_count"), ("共有ボタン", "share_tap_count"),
]
# 会長の目安（1 日あたり・2026-10-15）
TARGETS = {"impr_total": 4000, "pv_total": 150, "dl_first_total": 50}
TAB_MEMO = "メモ・基準値"


# 「メモ・基準値」タブの初期内容（#2231 の本文・週次コメントから移したもの・取れない項目の理由）。
# タブが無いときだけ書く（以後は手で直してよく、スクリプトは上書きしない）
MEMO_ROWS = [
    ["メモ・基準値（初回だけスクリプトが書く。以後は手で直してよい・上書きされない）"],
    ["由来", "https://github.com/hiroky1983/game_collection/issues/2231 （ASO の日次取得）・#2238（GA4・広告・スプレッドシート化）"],
    [],
    ["基準値（#2231 本文・10/3〜10/11 の 1 日平均。v1.1.11 公開前）"],
    ["インプレッション", "約 3,260"], ["プロダクトページ閲覧", "約 142"], ["初回 DL", "約 44.5"],
    ["押される割合（閲覧÷インプレッション）", "4.4%"],
    ["入れる割合（DL÷閲覧）", "27.8%（#2231 本文の値。週次コメントの期間合計の比では 31.1%）"],
    ["流入", "ほぼ全部 App Store 検索"],
    [],
    ["目安（会長・2026-10-15）", "1 日あたり"],
    ["初回 DL", "50 前後"], ["インプレッション", "4,000"], ["プロダクトページ閲覧", "150"],
    [],
    ["#2231 の週次コメント（10/5〜10/11 の週・2026-10-14 投稿）を転記", "前週", "前々週", "前々週比", "基準（10/3〜10/11）", "基準比"],
    ["インプレッション（合計）", "3,236.0", "3,348.5", "-3.4%", "3,261.0", "-0.8%"],
    ["インプレッション（ユニーク）", "2,624.3", "2,699.0", "-2.8%", "2,640.9", "-0.6%"],
    ["　うち日本", "3,178.4", "3,294.5", "-3.5%", "3,204.2", "-0.8%"],
    ["　うち日本以外", "57.6", "54.0", "+6.6%", "56.8", "+1.4%"],
    ["　うち検索", "3,200.1", "3,305.0", "-3.2%", "3,223.4", "-0.7%"],
    ["　うちブラウズ", "35.9", "43.5", "-17.6%", "37.6", "-4.5%"],
    ["　うち Web 参照", "0.0", "0.0", "—", "0.0", "—"],
    ["　うちアプリ参照", "0.0", "0.0", "—", "0.0", "—"],
    ["プロダクトページ閲覧", "140.9", "147.5", "-4.5%", "142.3", "-1.0%"],
    ["初回 DL", "43.3", "53.0", "-18.3%", "44.5", "-2.7%"],
    ["　うち日本", "43.0", "53.0", "-18.9%", "44.2", "-2.8%"],
    ["　うち日本以外", "0.3", "0.0", "—", "0.2", "+14.3%"],
    ["　うち検索", "42.3", "48.0", "-11.9%", "43.0", "-1.7%"],
    ["再 DL", "2.9", "4.0", "-28.6%", "3.0", "-4.8%"],
    ["押される割合（閲覧÷インプレッション）", "4.4%", "4.4%", "-0.1pt", "4.4%", "-0.0pt"],
    ["入れる割合（初回 DL÷閲覧）", "30.7%", "33.3%", "-2.6pt", "31.1%", "-0.4pt"],
    ["（データのある日数: 前週 7 日／前々週 インプレッション系 2 日・DL 系 1 日）"],
    [],
    ["取れない・欠ける項目と理由"],
    ["ASC（ASO）の 10/2 以前", "Analytics Reports API は日次インスタンスを数日分しか持たず、取得を始めた時点で 10/3 より前は残っていなかった"],
    ["GA4 の 2026-08-09 以前", "GA4 のデータが 2026-08-10 から（それ以前は計測していない）"],
    ["App Store 版の絞り込み（build_channel）の 2026-08-31 以前",
     "ユーザープロパティ build_channel が付き始めたのが 9/1 で、9/9 頃までは一部のユーザーにしか付いていない。全ビルドの列を併記している"],
    ["新規（first_open）の App Store 版の絞り込み", "first_open は build_channel が付く前に送られるため絞れない。全ビルドの件数"],
    ["広告収益・表示回数・クリック（10/14 以前）",
     "AdMob を GA4 にリンクしたのが 2026-10-15。それ以前は GA4 に無い（AdMob API は OAuth が要るため毎日の自動取得には入れていない・#2238）"],
    ["game_open・share_tap・reward_offer の古い日", "送り始めたのがそれぞれ v1.1.5・v1.1.6・v1.1.7 から。それより前の版の利用者の分は入らない"],
    ["国別のアクティブユーザー", "日本／日本以外の 2 区分のみ（App Store 版の絞り込みあり）"],
]


class SheetsError(Exception):
    pass


def _num(v):
    """CSV の値を数値に（空はそのまま空）。"""
    if v is None or v == "":
        return ""
    try:
        f = float(v)
    except ValueError:
        return v
    return int(f) if f.is_integer() else f


def _ga4_index(ga4_rows):
    """{(date, metric, game_id, ad_unit): value}"""
    return {(r["date"], r["metric"], r.get("game_id", ""), r.get("ad_unit", "")): r["value"] for r in ga4_rows}


def tab_aso(aso_rows):
    return [[ASO_HEADERS.get(c, c) for c in FIELDNAMES]] + [[_num(r.get(c, "")) for c in FIELDNAMES] for r in aso_rows]


def tab_ga4(ga4_rows):
    idx = _ga4_index(ga4_rows)
    dates = sorted(set(r["date"] for r in ga4_rows))
    out = [["日付"] + [h for h, _ in GA4_DAILY_COLS]]
    for d in dates:
        out.append([d] + [_num(idx.get((d, m, "", ""), "")) for _, m in GA4_DAILY_COLS])
    return out


def tab_games(ga4_rows):
    idx = _ga4_index(ga4_rows)
    keys = sorted(set((r["date"], r["game_id"]) for r in ga4_rows if r.get("game_id")))
    out = [["日付", "game_id", "ゲーム"] + [h for h, _ in GAME_DAILY_COLS]]
    for d, g in keys:
        out.append([d, "'" + g, GAME_NAMES.get(g, g)] + [_num(idx.get((d, m, g, ""), 0)) for _, m in GAME_DAILY_COLS])
    return out


def tab_ads(ga4_rows):
    idx = _ga4_index(ga4_rows)
    keys = sorted(set((r["date"], r.get("ad_unit", "")) for r in ga4_rows
                      if r["metric"] in ("ad_revenue", "ad_impressions", "ad_clicks") and not r.get("game_id")))
    out = [["日付", "広告フォーマット/ユニット", "収益 USD", "表示回数", "クリック", "1,000 回あたりの収益 USD"]]
    for d, u in keys:
        rev = _to_float(idx.get((d, "ad_revenue", "", u)))
        imp = to_int(idx.get((d, "ad_impressions", "", u)))
        out.append([d, u or "全体", rev, imp, to_int(idx.get((d, "ad_clicks", "", u))),
                    round(rev / imp * 1000, 4) if imp else ""])
    return out


def _avg(total_days):
    t, n = total_days
    return t / n if n else None


def _ratio(cur, base, pct=False):
    """前週比・基準比。件数は増減率、割合（pct）は差（ポイント）。"""
    if cur is None or base is None:
        return ""
    if pct:
        return "%+.1fpt" % (cur - base)
    if base == 0:
        return ""
    return "%+.1f%%" % ((cur / base - 1) * 100)


def weekly_metrics(aso_rows, ga4_rows):
    """週次まとめの指標: (見出し, 期間 → 1 日平均（割合は期間合計の比） or None, 割合か, 目安の列名) のリスト。"""
    def aso(num, den=None, kind="e"):
        return lambda s, e: period_value(aso_rows, s, e, num, den, kind)[0]

    def ga(metric, game=""):
        return lambda s, e: _avg(_ga4_sum(ga4_rows, metric, game, s, e))

    def ad(metric):
        return lambda s, e: _avg(_ga4_sum(ga4_rows, metric, "", s, e, days=_ad_days(ga4_rows, s, e)))

    def ecpm(s, e):
        days = _ad_days(ga4_rows, s, e)
        rev, _ = _ga4_sum(ga4_rows, "ad_revenue", "", s, e, days=days)
        imp, _ = _ga4_sum(ga4_rows, "ad_impressions", "", s, e, days=days)
        return rev / imp * 1000 if imp else None

    def days_aso(s, e):
        return period_value(aso_rows, s, e, "impr_total", None, "e")[1]

    def days_ga4(s, e):
        return _ga4_sum(ga4_rows, "active_users_all", "", s, e)[1]

    m = [("データのある日数（ASO）", days_aso, None, None), ("データのある日数（GA4）", days_ga4, None, None)]
    m += [(label, aso(num, den, kind), den is not None, num if den is None else None)
          for label, num, den, kind in (
              ("インプレッション（合計）", "impr_total", None, "e"), ("インプレッション（ユニーク）", "impr_unique", None, "e"),
              ("　うち日本", "impr_total_jp", None, "e"), ("　うち日本以外", "impr_total_other", None, "e"),
              ("　うち検索", "impr_search", None, "e"), ("　うちブラウズ", "impr_browse", None, "e"),
              ("　うち Web 参照", "impr_web", None, "e"), ("　うちアプリ参照", "impr_app", None, "e"),
              ("プロダクトページ閲覧", "pv_total", None, "e"), ("初回 DL", "dl_first_total", None, "d"),
              ("　うち日本", "dl_first_jp", None, "d"), ("　うち日本以外", "dl_first_other", None, "d"),
              ("　うち検索", "dl_first_search", None, "d"), ("再 DL", "dl_redownload_total", None, "d"),
              ("押される割合 %（閲覧÷インプレッション）", "pv_total", "impr_total", "e"),
              ("入れる割合 %（初回 DL÷閲覧）", "dl_first_total", "pv_total", "ed"))]
    m += [(label, ga(metric), False, None) for label, metric in (
        ("アクティブユーザー（App Store 版）", "active_users"), ("アクティブユーザー（全ビルド）", "active_users_all"),
        ("　うち日本（App Store 版）", "active_users_jp"), ("　うち日本以外（App Store 版）", "active_users_other"),
        ("新規（first_open・全ビルド）", "new_users"), ("セッション（App Store 版）", "sessions"),
        ("ゲームを開いた（game_open）", "game_open_count"), ("プレイ開始（game_start）", "game_start_count"),
        ("プレイ終了（game_end）", "game_end_count"), ("広告の提示（reward_offer）", "reward_offer_count"),
        ("広告の要求（reward_request）", "reward_request_count"), ("広告の視聴完了（reward_ad）", "reward_ad_count"),
        ("共有ボタン（share_tap）", "share_tap_count"))]
    m += [("広告収益 USD", ad("ad_revenue"), False, None), ("広告の表示回数", ad("ad_impressions"), False, None),
          ("広告のクリック", ad("ad_clicks"), False, None), ("1,000 回あたりの収益 USD（eCPM 相当）", ecpm, False, None)]
    m += [("プレイ開始 " + GAME_NAMES.get(g, g), ga("game_start_count", g), False, None) for g in GA4_WATCH_GAMES]
    m += [("プレイした人数 " + GAME_NAMES.get(g, g), ga("game_start_users", g), False, None) for g in GA4_WATCH_GAMES]
    return m


def _r(v):
    return round(v, 2) if isinstance(v, float) else ("" if v is None else v)


def tab_weekly(aso_rows, ga4_rows, today, status):
    """週次まとめ: 先頭に状態とグラフ、WEEKLY_TABLE_ROW 行目から表（行 = 指標、列 = 基準・目安・週。新しい週が左）。
    各週は「1 日平均・前週比・基準比」の 3 列。基準は v1.1.11 公開前の 10/3〜10/11。
    広告は表示回数 0 の日（AdMob リンク前）をデータなしとして平均から除く。"""
    dates = [r["date"] for r in aso_rows] + [r["date"] for r in ga4_rows]
    weeks = []
    if dates:
        ws = parse_date(min(dates))
        ws -= datetime.timedelta(days=ws.weekday())
        # 終わった週に加え、今日より前の日を含む途中の週も出す（見出しに「途中」と付ける）
        last = today - datetime.timedelta(days=today.weekday() + (7 if today.weekday() == 0 else 0))
        while ws <= last:
            weeks.append(ws)
            ws += datetime.timedelta(days=7)
    weeks.reverse()
    head = ["指標", "基準（%d/%d〜%d/%d）" % (BASELINE_START.month, BASELINE_START.day, BASELINE_END.month, BASELINE_END.day),
            "目安（会長）"]
    for ws in weeks:
        we = ws + datetime.timedelta(days=6)
        label = "%d/%d〜%d/%d" % (ws.month, ws.day, we.month, we.day) + ("（途中）" if we >= today else "")
        head += [label, "前週比", "基準比"]
    table = [head]
    for label, f, pct, target in weekly_metrics(aso_rows, ga4_rows):
        counts_days = pct is None
        base = None if counts_days else f(BASELINE_START, BASELINE_END)
        row = [label, _r(base), TARGETS.get(target, "")]
        for ws in weeks:
            cur = f(ws, ws + datetime.timedelta(days=6))
            if counts_days:
                row += [cur, "", ""]
                continue
            prev = f(ws - datetime.timedelta(days=7), ws - datetime.timedelta(days=1))
            row += [_r(cur), _ratio(cur, prev, pct), _ratio(cur, base, pct)]
        table.append(row)
    note = ["1 日平均（データの無い日は除く。割合は期間合計の比）。前週比・基準比は件数は増減率、割合は差（ポイント）。"
            "基準は v1.1.11（10/12 公開）前の 10/3〜10/11。広告は表示回数 0 の日（AdMob の GA4 リンク前）を除く。"
            "ASO は App Store Connect、それ以外は GA4。表は新しい週が左。由来と取れない項目は「%s」タブ" % TAB_MEMO]
    top = [[s] for s in status] + [note]
    return top + [[] for _ in range(WEEKLY_TABLE_ROW - 1 - len(top))] + table


def status_lines(now, errors):
    """週次まとめの先頭の行。errors: [(どの取得, 内容)]"""
    stamp = now.strftime("%Y-%m-%d %H:%M JST")
    if not errors:
        return ["最終更新: %s（ASC・GA4 とも取得成功）" % stamp]
    return ["取得失敗: %s・%s — %s" % (stamp, what, msg) for what, msg in errors] + ["最終更新: %s（失敗した取得は前回までの数字のまま）" % stamp]


def build_tabs(aso_rows, ga4_rows, today, now, errors):
    return {
        TAB_WEEKLY: tab_weekly(aso_rows, ga4_rows, today, status_lines(now, errors)),
        TAB_ASO: tab_aso(aso_rows),
        TAB_GA4: tab_ga4(ga4_rows),
        TAB_GAMES: tab_games(ga4_rows),
        TAB_ADS: tab_ads(ga4_rows),
    }


def _chart(title, sheet_id, x_col, y_cols, anchor_sheet, row, col):
    def src(c):
        return {"sourceRange": {"sources": [{"sheetId": sheet_id, "startRowIndex": 0, "endRowIndex": CHART_ROWS,
                                             "startColumnIndex": c, "endColumnIndex": c + 1}]}}
    return {"addChart": {"chart": {
        "spec": {"title": title, "basicChart": {
            "chartType": "LINE", "legendPosition": "BOTTOM_LEGEND" if len(y_cols) > 1 else "NO_LEGEND",
            "headerCount": 1,
            "axis": [{"position": "BOTTOM_AXIS", "title": "日付"}, {"position": "LEFT_AXIS"}],
            "domains": [{"domain": src(x_col)}],
            "series": [{"series": src(c), "targetAxis": "LEFT_AXIS"} for c in y_cols]}},
        "position": {"overlayPosition": {"anchorCell": {"sheetId": anchor_sheet, "rowIndex": row, "columnIndex": col},
                                         "widthPixels": 600, "heightPixels": 400}}}}}


def chart_requests(ids):
    """週次まとめに置く日次の折れ線 4 本（初回 DL・インプレッション・アクティブユーザー・広告収益）。"""
    w = ids[TAB_WEEKLY]
    ga4_col = {m: i + 1 for i, (_, m) in enumerate(GA4_DAILY_COLS)}
    return [
        _chart("初回 DL（日次）", ids[TAB_ASO], 0, [FIELDNAMES.index("dl_first_total")], w, 4, 0),
        _chart("インプレッション（日次）", ids[TAB_ASO], 0, [FIELDNAMES.index("impr_total")], w, 4, 6),
        _chart("アクティブユーザー（日次）", ids[TAB_GA4], 0,
               [ga4_col["active_users"], ga4_col["active_users_all"]], w, 25, 0),
        _chart("広告収益 USD（日次）", ids[TAB_GA4], 0, [ga4_col["ad_revenue"]], w, 25, 6),
    ]


class Sheets:
    def __init__(self, tok):
        self.tok = tok

    def call(self, method, path, body=None):
        req = urllib.request.Request(SHEETS_API + path, method=method,
                                     data=json.dumps(body).encode() if body is not None else None,
                                     headers={"Authorization": "Bearer " + self.tok, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.loads(resp.read() or b"{}")
        except urllib.error.HTTPError as e:
            msg = ""
            try:
                msg = (json.loads(e.read()).get("error") or {}).get("message", "")[:200]
            except Exception:
                pass
            raise SheetsError("Sheets API が HTTP %d を返しました %s" % (e.code, msg))
        except urllib.error.URLError:
            raise SheetsError("Sheets API に接続できませんでした")


def write_sheets(api, tabs):
    """タブを揃え（無ければ作る・既定の「シート1」は週次まとめに名前を変える）、中身を丸ごと書き、グラフを置き直す。"""
    meta = api.call("GET", "?fields=sheets(properties(sheetId,title),charts(chartId))")
    sheets = {s["properties"]["title"]: s for s in meta.get("sheets") or []}
    reqs = []
    if TAB_WEEKLY not in sheets:
        default = next((t for t in DEFAULT_SHEET_TITLES if t in sheets), None)
        if default:
            reqs.append({"updateSheetProperties": {"properties": {"sheetId": sheets[default]["properties"]["sheetId"],
                                                                  "title": TAB_WEEKLY, "index": 0},
                                                   "fields": "title,index"}})
    for i, t in enumerate(TABS):
        if t not in sheets and not (t == TAB_WEEKLY and reqs):
            reqs.append({"addSheet": {"properties": {"title": t, "index": i}}})
    if reqs:
        api.call("POST", ":batchUpdate", {"requests": reqs})
        meta = api.call("GET", "?fields=sheets(properties(sheetId,title),charts(chartId))")
        sheets = {s["properties"]["title"]: s for s in meta.get("sheets") or []}
    ids = {t: sheets[t]["properties"]["sheetId"] for t in TABS}
    if TAB_MEMO not in sheets:
        # メモは初回だけ書く（以後は会長・社長が手で直すので上書きしない）
        api.call("POST", ":batchUpdate", {"requests": [{"addSheet": {"properties": {"title": TAB_MEMO}}}]})
        api.call("PUT", "/values/%s?valueInputOption=RAW" % urllib.parse.quote("'%s'!A1" % TAB_MEMO),
                 {"values": MEMO_ROWS})
    api.call("POST", "/values:batchClear", {"ranges": ["'%s'" % t for t in TABS]})
    def cell(v):
        # USER_ENTERED では「+22.3%」が数式として読まれるため、符号で始まる文字列（前週比など）は文字列のまま入れる
        return "'" + v if isinstance(v, str) and v[:1] in "+-=" and v != "" else v

    api.call("POST", "/values:batchUpdate", {"valueInputOption": "USER_ENTERED", "data": [
        {"range": "'%s'!A1" % t, "values": [[cell(v) for v in r] for r in tabs[t]]} for t in TABS]})
    old = [c["chartId"] for c in sheets[TAB_WEEKLY].get("charts") or []]
    reqs = [{"deleteEmbeddedObject": {"objectId": c}} for c in old] + chart_requests(ids)
    reqs.append({"updateSheetProperties": {"properties": {"sheetId": ids[TAB_WEEKLY],
                                                          "gridProperties": {"frozenRowCount": 0}},
                                           "fields": "gridProperties.frozenRowCount"}})
    api.call("POST", ":batchUpdate", {"requests": reqs})


def dump_tabs(tabs, out_dir):
    """API を呼ばずに各タブの中身を <out_dir>/<タブ名>.tsv に出す（テスト用）。"""
    os.makedirs(out_dir, exist_ok=True)
    for t, rows in tabs.items():
        with open(os.path.join(out_dir, t + ".tsv"), "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f, delimiter="\t", lineterminator="\n")
            for r in rows:
                w.writerow(["" if v is None else v for v in r])


# ---------------------------------------------------------------- 本体

def parse_date(s):
    return datetime.datetime.strptime(s, "%Y-%m-%d").date()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out-dir", default=os.environ.get("ASO_OUT_DIR", os.path.expanduser("~/asobiba-kpi/aso")))
    ap.add_argument("--no-fetch", action="store_true", help="ASC・GA4 の API を呼ばず保存済みの数字から作り直すだけ")
    ap.add_argument("--import-engagement-tsv", nargs="*", default=[], metavar="TSV",
                    help="Discovery and Engagement の TSV を raw/ へ取り込む（ファイル名 = processingDate.tsv）")
    ap.add_argument("--import-downloads-tsv", nargs="*", default=[], metavar="TSV",
                    help="App Downloads の TSV を raw/ へ取り込む（ファイル名 = processingDate.tsv）")
    ap.add_argument("--today", type=parse_date, help="今日の日付（JST）を上書き。テスト用")
    ap.add_argument("--ga4-out-dir", help="GA4 の保存先（既定: --out-dir と同じ階層の ga4/ = ~/asobiba-kpi/ga4）")
    ap.add_argument("--no-ga4", action="store_true", help="GA4 を取らない")
    ap.add_argument("--ga4-from-json", metavar="DIR",
                    help="GA4 API を呼ばず DIR/<ga4_queries のキー>.json（runReport の応答）を取り込む。テスト用")
    ap.add_argument("--no-sheets", action="store_true", help="スプレッドシートに書かない")
    ap.add_argument("--sheets-dump", metavar="DIR",
                    help="スプレッドシートに書く代わりに各タブの中身を DIR/<タブ名>.tsv に出す（API は呼ばない）")
    a = ap.parse_args(argv)

    raw_dir = os.path.join(a.out_dir, "raw")
    daily_path = os.path.join(a.out_dir, "daily.csv")
    today = a.today or datetime.datetime.now(JST).date()
    errors = []  # [(どの取得, 内容)]。スプレッドシートの先頭に出す

    for kind, files in (("engagement", a.import_engagement_tsv), ("downloads", a.import_downloads_tsv)):
        for src in files:
            pdate = os.path.splitext(os.path.basename(src))[0]
            parse_date(pdate)  # ファイル名が日付でなければここで落とす
            dest = os.path.join(raw_dir, kind, pdate + ".tsv")
            if os.path.exists(dest):
                continue
            with open(src, "rb") as f:
                data = f.read()
            write_atomic(dest, lambda f: f.write(data), mode="wb")
            log("取り込み: %s/%s.tsv" % (kind, pdate))

    ga4_dir = a.ga4_out_dir or os.path.join(os.path.dirname(os.path.abspath(a.out_dir)), "ga4")
    ga4_path = os.path.join(ga4_dir, "daily.csv")
    ga4_rows = read_ga4_daily(ga4_path)

    # GA4 と ASC は互いに独立。片方が失敗しても、もう片方の取得・保存とスプレッドシートへの書き込みは続ける
    if not a.no_ga4 and (a.ga4_from_json or not a.no_fetch):
        try:
            if a.ga4_from_json:
                reports = {}
                for name in ga4_queries(today, today):
                    fp = os.path.join(a.ga4_from_json, name + ".json")
                    if os.path.exists(fp):
                        with open(fp, encoding="utf-8") as f:
                            reports[name] = json.load(f)
                new = ga4_rows_from_reports(reports)
            else:
                new = fetch_ga4(ga4_rows, today)
            ga4_rows = merge_ga4(ga4_rows, new)
            write_ga4_daily(ga4_path, ga4_rows)
            days = sorted(set(r["date"] for r in ga4_rows))
            if days:
                log("GA4 daily.csv: %d 行（%s〜%s の %d 日分）" % (len(ga4_rows), days[0], days[-1], len(days)))
        except Ga4Error as e:
            errors.append(("GA4", str(e)))
        except Exception as e:  # 想定外の失敗でも ASC 側は止めない（中身は鍵・トークンを含みうるので型名だけ出す）
            errors.append(("GA4", "取得・保存に失敗しました（%s）" % type(e).__name__))

    if not a.no_fetch:
        try:
            fetch(raw_dir)
        except AscError as e:
            errors.append(("ASC（App Store Connect）", str(e)))
        except Exception as e:
            errors.append(("ASC（App Store Connect）", "取得に失敗しました（%s）" % type(e).__name__))

    rows = build_daily(raw_dir, read_daily(daily_path))
    if rows:
        write_daily(daily_path, rows)
        log("daily.csv: %d 日分（%s〜%s）" % (len(rows), rows[0]["date"], rows[-1]["date"]))
    for what, msg in errors:
        log("エラー: %s: %s" % (what, msg))

    if a.sheets_dump or not a.no_sheets:
        tabs = build_tabs(rows, ga4_rows, today, datetime.datetime.now(JST), errors)
        try:
            if a.sheets_dump:
                dump_tabs(tabs, a.sheets_dump)
            else:
                write_sheets(Sheets(google_token(SHEETS_SCOPE)), tabs)
                log("スプレッドシート: %s" % ", ".join("%s %d 行" % (t, max(0, len(tabs[t]) - 1)) for t in TABS[1:]))
        except (Ga4Error, SheetsError) as e:
            errors.append(("スプレッドシート", str(e)))
            log("エラー: スプレッドシート: %s" % e)
        except Exception as e:
            errors.append(("スプレッドシート", type(e).__name__))
            log("エラー: スプレッドシートへの書き込みに失敗しました（%s）" % type(e).__name__)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
