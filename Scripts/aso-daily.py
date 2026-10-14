#!/usr/bin/env python3
"""ASO の日次の数字を App Store Connect から取って保存し、毎週の表を作る（Issue #2231）。

なぜ要るか: App Analytics（Analytics Reports API）の日次インスタンスは数日分しか保持されないため、
毎日取ってローカルに貯めないと v1.1.11 以降の推移が追えない。

やること（launchd から毎日 1 回。仕組みと入れ方・止め方は docs/ai-devops.md「ASO の日次取得」）:
  1. 既存の ONGOING リクエスト（REQUEST_ID）から「App Store Discovery and Engagement Standard」
     「App Downloads Standard」の DAILY インスタンスを一覧し、まだ保存していない processingDate の分を
     ~/asobiba-kpi/aso/raw/<種類>/<processingDate>.tsv に保存する（Mac が止まっていた日の分も、
     API に残っている範囲で次回に取り戻す）
  2. raw/ の全ファイルから daily.csv を作り直す。1 つの日付は複数のインスタンスに重複して入るため、
     その日付を含むファイルのうち processingDate が最も新しいものだけを使う（= 重複排除）。
     raw/ に無くなった日付は既存の daily.csv の行を残す
  3. 直近に終わった週（月〜日）の 1 日平均・前々週比・基準期間との比較を Issue #2231 にコメントする。
     通常は月曜（JST）の実行で投稿され、月曜に Mac が止まっていて実行を逃した週は次の実行で取り戻す。
     コメントに週の印（<!-- aso-weekly:YYYY-MM-DD -->）を埋め、同じ週には二重に投稿しない
     （投稿済みの週は weekly-posted.txt に控え、控えに無ければ Issue のコメントを見て確かめる）

  4. GA4（#2238）: App Store 版のアクティブユーザー・新規（first_open）・game_start / game_open /
     reward_request / reward_ad（全体とゲーム別）・広告収益（AdMob リンク経由）を取り、
     ~/asobiba-kpi/ga4/daily.csv に保存する。直近 3 日は毎回取り直して上書き。週次コメントに GA4 の節を足す。
     失敗しても ASC 側は止めず、ログと週次コメントに失敗を明記する

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
ISSUE = "2231"
REPO = "hiroky1983/game_collection"
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


# ---------------------------------------------------------------- 週の表

# (表示名, 分子の列, 分母の列 or None, 種類)。分母があるものは期間合計の比（%）
WEEKLY_METRICS = [
    ("インプレッション（合計）", "impr_total", None, "e"),
    ("インプレッション（ユニーク）", "impr_unique", None, "e"),
    ("　うち日本", "impr_total_jp", None, "e"),
    ("　うち日本以外", "impr_total_other", None, "e"),
    ("　うち検索", "impr_search", None, "e"),
    ("　うちブラウズ", "impr_browse", None, "e"),
    ("　うち Web 参照", "impr_web", None, "e"),
    ("　うちアプリ参照", "impr_app", None, "e"),
    ("プロダクトページ閲覧", "pv_total", None, "e"),
    ("初回 DL", "dl_first_total", None, "d"),
    ("　うち日本", "dl_first_jp", None, "d"),
    ("　うち日本以外", "dl_first_other", None, "d"),
    ("　うち検索", "dl_first_search", None, "d"),
    ("再 DL", "dl_redownload_total", None, "d"),
    ("押される割合（閲覧÷インプレッション）", "pv_total", "impr_total", "e"),
    ("入れる割合（初回 DL÷閲覧）", "dl_first_total", "pv_total", "ed"),
]


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


def _fmt(v, pct):
    if v is None:
        return "—"
    return "%.1f%%" % v if pct else "{:,.1f}".format(v)


def _diff(a, b, pct):
    if a is None or b is None:
        return "—"
    if pct:
        return "%+.1fpt" % (a - b)
    if b == 0:
        return "—"
    return "%+.1f%%" % ((a / b - 1) * 100)


def weekly_marker(week_start):
    return "<!-- aso-weekly:%s -->" % week_start.isoformat()


def weekly_report(rows, week_start, ga4=None):
    """week_start（月曜）から 7 日間を「前週」とした週次コメントの本文（Markdown）。
    ga4 = (GA4 の行, 今回の取得の失敗内容 or None) を渡すと GA4 の節を足す。"""
    ws, we = week_start, week_start + datetime.timedelta(days=6)
    ps, pe = ws - datetime.timedelta(days=7), ws - datetime.timedelta(days=1)
    v_end = we if we >= V1111_START else V1111_START
    _, e_days = period_value(rows, ws, we, "impr_total", None, "e")
    _, d_days = period_value(rows, ws, we, "dl_first_total", None, "d")
    _, pe_days = period_value(rows, ps, pe, "impr_total", None, "e")
    _, pd_days = period_value(rows, ps, pe, "dl_first_total", None, "d")

    def md(d):
        return "%d/%d" % (d.month, d.day)

    lines = [
        weekly_marker(ws),
        "## ASO 週次（%s〜%s）" % (md(ws), md(we)),
        "",
        "1 日平均（割合は期間合計の比）。データの無い日は平均から除く。",
        "データのある日数: 前週 インプレッション系 %d 日・DL 系 %d 日／前々週 %d 日・%d 日"
        % (e_days, d_days, pe_days, pd_days),
        "",
        "| 指標 | 前週 | 前々週 | 前々週比 | 基準（%s〜%s） | 基準比 | v1.1.11 以降（%s〜） |"
        % (md(BASELINE_START), md(BASELINE_END), md(V1111_START)),
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for label, num, den, kind in WEEKLY_METRICS:
        pct = den is not None
        cur, _ = period_value(rows, ws, we, num, den, kind)
        prev, _ = period_value(rows, ps, pe, num, den, kind)
        base, _ = period_value(rows, BASELINE_START, BASELINE_END, num, den, kind)
        v11, _ = period_value(rows, V1111_START, v_end, num, den, kind) if we >= V1111_START else (None, 0)
        lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (
            label, _fmt(cur, pct), _fmt(prev, pct), _diff(cur, prev, pct),
            _fmt(base, pct), _diff(cur, base, pct), _fmt(v11, pct)))
    lines += [
        "",
        "前々週比・基準比は、件数は増減率、割合は差（ポイント）。"
        "出典: App Store Connect Analytics Reports（`Scripts/aso-daily.py` が毎日取得し `~/asobiba-kpi/aso/daily.csv` に保存）。",
    ]
    if ga4 is not None:
        lines += ga4_weekly_section(ga4[0], ws, ga4[1])
    return "\n".join(lines) + "\n"


def last_complete_week_start(today):
    """today より前に終わった直近の週（月〜日）の月曜。"""
    this_monday = today - datetime.timedelta(days=today.weekday())
    return this_monday - datetime.timedelta(days=7)


# ---------------------------------------------------------------- GitHub（週次コメント）

def gh_cmd():
    return os.environ.get("ASO_GH", "gh")


def already_posted(marker):
    out = subprocess.run(
        [gh_cmd(), "api", "--paginate", "repos/%s/issues/%s/comments" % (REPO, ISSUE), "--jq", ".[].body"],
        capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        raise RuntimeError("Issue のコメント一覧を取れませんでした（gh 終了コード %d）" % out.returncode)
    return marker in out.stdout


def _posted_local(state_path):
    try:
        with open(state_path, encoding="utf-8") as f:
            return set(ln.strip() for ln in f if ln.strip())
    except FileNotFoundError:
        return set()


def _mark_posted(state_path, week_start):
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    with open(state_path, "a", encoding="utf-8") as f:
        f.write(week_start.isoformat() + "\n")


def post_weekly(rows, week_start, state_path, ga4=None):
    """week_start の週を投稿する。投稿済み（控え or Issue のコメントに印がある）なら何もしない。"""
    if week_start.isoformat() in _posted_local(state_path):
        return None
    if already_posted(weekly_marker(week_start)):
        log("週次: %s の週は投稿済みのため見送り" % week_start.isoformat())
        _mark_posted(state_path, week_start)
        return None
    body = weekly_report(rows, week_start, ga4)
    fd, tmp = tempfile.mkstemp(prefix="aso-weekly-", suffix=".md")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(body)
        out = subprocess.run([gh_cmd(), "issue", "comment", ISSUE, "--repo", REPO, "--body-file", tmp],
                             capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(tmp)
    if out.returncode != 0:
        raise RuntimeError("週次コメントの投稿に失敗しました（gh 終了コード %d）" % out.returncode)
    url = out.stdout.strip()
    _mark_posted(state_path, week_start)
    log("週次: %s の週を投稿 %s" % (week_start.isoformat(), url))
    return url


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
GA4_BACKFILL_START = datetime.date(2026, 9, 1)  # daily.csv が空のときに遡る日
GA4_REFETCH_DAYS = 3  # 直近は数字が変わるので毎回取り直す日数（昨日を含む）
GA4_EVENTS = ["game_start", "game_open", "reward_request", "reward_ad"]
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
    """{"active"|"events"|"events_by_game"|"first_open"|"ads"|"ads_by_unit": runReport の応答} → 縦持ちの行。
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


def ga4_token():
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
                             "scope": "https://www.googleapis.com/auth/analytics.readonly",
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
    tok = ga4_token()
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


def ga4_ad_section(rows, ws, we, ps, pe):
    """広告収益・表示回数・1,000 回あたりの収益の節。表示回数 0 の日はデータなしとして平均に含めない。"""
    cd, pdays = _ad_days(rows, ws, we), _ad_days(rows, ps, pe)
    lines = ["", "### 広告収益（AdMob・GA4 経由）", ""]
    if not cd:
        return lines + ["前週は広告のデータがありません（AdMob の GA4 リンク前、または表示回数 0 の日だけ）。"]

    def stats(s, e, days):
        rev, _ = _ga4_sum(rows, "ad_revenue", "", s, e, days=days)
        imp, _ = _ga4_sum(rows, "ad_impressions", "", s, e, days=days)
        clk, _ = _ga4_sum(rows, "ad_clicks", "", s, e, days=days)
        n = len(days)
        if not n:
            return None, None, None, None
        return rev / n, imp / n, clk / n, (rev / imp * 1000 if imp else None)

    c, p = stats(ws, we, cd), stats(ps, pe, pdays)

    def money(v):
        return "—" if v is None else "$%.2f" % v

    lines += ["1 日平均（表示回数 0 の日はデータなしとして除く）。データのある日数: 前週 %d 日／前々週 %d 日。通貨は USD"
              % (len(cd), len(pdays)), "",
              "| 指標 | 前週 | 前々週 | 前々週比 |", "|---|---:|---:|---:|",
              "| 広告収益 | %s | %s | %s |" % (money(c[0]), money(p[0]), _diff(c[0], p[0], False)),
              "| 表示回数 | %s | %s | %s |" % (_fmt(c[1], False), _fmt(p[1], False), _diff(c[1], p[1], False)),
              "| クリック数 | %s | %s | %s |" % (_fmt(c[2], False), _fmt(p[2], False), _diff(c[2], p[2], False)),
              "| 1,000 回あたりの収益（eCPM 相当・期間合計の比） | %s | %s | %s |"
              % (money(c[3]), money(p[3]), _diff(c[3], p[3], False))]
    units = sorted(set(r["ad_unit"] for r in rows if r.get("ad_unit")))
    by_unit = []
    for u in units:
        rev, _ = _ga4_sum(rows, "ad_revenue", "", ws, we, unit=u, days=cd)
        imp, _ = _ga4_sum(rows, "ad_impressions", "", ws, we, unit=u, days=cd)
        if imp or rev:
            by_unit.append((rev, imp, u))
    if by_unit:
        lines += ["", "| 広告フォーマット/ユニット（前週の合計） | 収益 | 表示回数 | 1,000 回あたり |", "|---|---:|---:|---:|"]
        for rev, imp, u in sorted(by_unit, key=lambda x: (-x[0], x[2])):
            lines.append("| %s | %s | {:,} | %s |".format(imp) % (u, money(rev), money(rev / imp * 1000 if imp else None)))
    return lines


def _game_label(g):
    n = GAME_NAMES.get(g)
    return "%s（%s）" % (n, g) if n and n != g else g


def ga4_weekly_section(rows, week_start, error=None):
    """週次コメントの GA4 の節（Markdown の行のリスト）。error は今回の取得の失敗内容（あれば先頭に出す）。"""
    ws, we = week_start, week_start + datetime.timedelta(days=6)
    ps, pe = ws - datetime.timedelta(days=7), ws - datetime.timedelta(days=1)
    lines = ["", "## GA4（App Store 版）"]
    if error:
        lines += ["", "**⚠ GA4 の取得に失敗しました: %s**" % error,
                  "以下は前回までに保存した数字です（直近の日は欠けている・古い可能性があります）。"]
    _, cur_days = _ga4_sum(rows, "active_users", "", ws, we)
    _, prev_days = _ga4_sum(rows, "active_users", "", ps, pe)
    if cur_days == 0:
        lines += ["", "前週のデータがありません（`~/asobiba-kpi/ga4/daily.csv` に該当日の行が無い）。"]
        return lines

    def avg(metric, game, s, e):
        t, n = _ga4_sum(rows, metric, game, s, e)
        return (t / n) if n else None

    lines += ["", "1 日平均。データのある日数: 前週 %d 日／前々週 %d 日" % (cur_days, prev_days), "",
              "| 指標 | 前週 | 前々週 | 前々週比 |", "|---|---:|---:|---:|"]
    for label, metric in (("アクティブユーザー", "active_users"), ("新規（first_open・全ビルド）", "new_users"),
                          ("プレイ数（game_start）", "game_start_count"), ("ゲームを開いた（game_open）", "game_open_count"),
                          ("広告の要求（reward_request）", "reward_request_count"),
                          ("広告の視聴完了（reward_ad）", "reward_ad_count")):
        c, p = avg(metric, "", ws, we), avg(metric, "", ps, pe)
        lines.append("| %s | %s | %s | %s |" % (label, _fmt(c, False), _fmt(p, False), _diff(c, p, False)))

    games = set(r["game_id"] for r in rows if r.get("game_id"))
    plays = sorted(((_ga4_sum(rows, "game_start_count", g, ws, we)[0], g) for g in games), key=lambda x: (-x[0], x[1]))
    lines += ["", "### プレイ数の上位 5 ゲーム（前週の合計）", "",
              "| 順位 | ゲーム | プレイ数 | 1 日平均の人数 | 前々週のプレイ数 | 前々週比 |", "|---:|---|---:|---:|---:|---:|"]
    for i, (n, g) in enumerate([x for x in plays if x[0] > 0][:5], 1):
        p, _ = _ga4_sum(rows, "game_start_count", g, ps, pe)
        lines.append("| %d | %s | {:,} | %s | {:,} | %s |".format(n, p) % (
            i, _game_label(g), _fmt(avg("game_start_users", g, ws, we), False), _diff(n, p, False)))

    lines += ["", "### 新ゲームと柵越えおじさんの推移（プレイ数／人数）", "",
              "| 日付 | " + " | ".join(_game_label(g) for g in GA4_WATCH_GAMES) + " |",
              "|---|" + "---:|" * len(GA4_WATCH_GAMES)]
    for i in range(7):
        d = ws + datetime.timedelta(days=i)
        cells = []
        for g in GA4_WATCH_GAMES:
            c, has = _ga4_sum(rows, "game_start_count", g, d, d)
            u, _ = _ga4_sum(rows, "game_start_users", g, d, d)
            cells.append("%d／%d" % (c, u) if has else "0")
        lines.append("| %d/%d | %s |" % (d.month, d.day, " | ".join(cells)))
    cells = []
    for g in GA4_WATCH_GAMES:
        c, _ = _ga4_sum(rows, "game_start_count", g, ws, we)
        p, _ = _ga4_sum(rows, "game_start_count", g, ps, pe)
        cells.append("{:,}（前々週 {:,}）".format(c, p))
    lines.append("| 週計 | %s |" % " | ".join(cells))

    ad, _ = _ga4_sum(rows, "reward_ad_count", "", ws, we)
    req, _ = _ga4_sum(rows, "reward_request_count", "", ws, we)
    pad, _ = _ga4_sum(rows, "reward_ad_count", "", ps, pe)
    by_game = sorted(((_ga4_sum(rows, "reward_ad_count", g, ws, we)[0], g) for g in games), key=lambda x: (-x[0], x[1]))
    lines += ["", "### 広告（リワード）の視聴", "",
              "前週の視聴完了 {:,} 回（前々週 {:,} 回・{}）、要求 {:,} 回、完了率 {}。".format(
                  ad, pad, _diff(ad, pad, False), req, ("%.1f%%" % (ad / req * 100)) if req else "—")]
    top = [x for x in by_game if x[0] > 0][:5]
    if top:
        lines.append("ゲーム別の視聴完了（上位 5）: " + "、".join("%s %d 回" % (_game_label(g), n) for n, g in top))
    lines += ga4_ad_section(rows, ws, we, ps, pe)
    lines += ["", "出典: GA4 Data API（プロパティ %s・`customUser:build_channel = appstore` で絞り込み。"
                  "新規（first_open に build_channel が付かない）と広告収益は全ビルド）。`~/asobiba-kpi/ga4/daily.csv` に保存。"
              % GA4_PROPERTY]
    return lines


# ---------------------------------------------------------------- 本体

def parse_date(s):
    return datetime.datetime.strptime(s, "%Y-%m-%d").date()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out-dir", default=os.environ.get("ASO_OUT_DIR", os.path.expanduser("~/asobiba-kpi/aso")))
    ap.add_argument("--no-fetch", action="store_true", help="API を呼ばず raw/ から daily.csv を作り直すだけ")
    ap.add_argument("--import-engagement-tsv", nargs="*", default=[], metavar="TSV",
                    help="Discovery and Engagement の TSV を raw/ へ取り込む（ファイル名 = processingDate.tsv）")
    ap.add_argument("--import-downloads-tsv", nargs="*", default=[], metavar="TSV",
                    help="App Downloads の TSV を raw/ へ取り込む（ファイル名 = processingDate.tsv）")
    ap.add_argument("--today", type=parse_date, help="今日の日付（JST）を上書き。テスト用")
    ap.add_argument("--no-weekly", action="store_true", help="週次コメントを投稿しない")
    ap.add_argument("--print-weekly", type=parse_date, metavar="MONDAY",
                    help="MONDAY から始まる週の週次コメントの本文を標準出力に出すだけ（投稿しない）")
    ap.add_argument("--ga4-out-dir", help="GA4 の保存先（既定: --out-dir と同じ階層の ga4/ = ~/asobiba-kpi/ga4）")
    ap.add_argument("--no-ga4", action="store_true", help="GA4 を取らない（週次にも GA4 の節を出さない）")
    ap.add_argument("--ga4-from-json", metavar="DIR",
                    help="GA4 API を呼ばず DIR/<active|events|events_by_game|first_open|ads|ads_by_unit>.json"
                         "（runReport の応答）を取り込む。テスト用")
    a = ap.parse_args(argv)

    raw_dir = os.path.join(a.out_dir, "raw")
    daily_path = os.path.join(a.out_dir, "daily.csv")
    today = a.today or datetime.datetime.now(JST).date()

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
    ga4_rows, ga4_error = read_ga4_daily(ga4_path), None

    status = 0
    # GA4 は ASC より先に取る（ASC が失敗しても GA4 は保存する。逆も同じ）
    if not a.no_ga4 and a.print_weekly is None and (a.ga4_from_json or not a.no_fetch):
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
            ga4_error = str(e)
        except Exception as e:  # 想定外の失敗でも ASC 側は止めない（中身は鍵・トークンを含みうるので型名だけ出す）
            ga4_error = "GA4 の取得・保存に失敗しました（%s）" % type(e).__name__
        if ga4_error:
            log("エラー: GA4: %s" % ga4_error)
            status = 1
    ga4 = None if a.no_ga4 else (ga4_rows, ga4_error)

    if not a.no_fetch and a.print_weekly is None:
        try:
            fetch(raw_dir)
        except AscError as e:
            log("エラー: %s" % e)
            status = 1
        except (urllib.error.URLError, OSError, subprocess.TimeoutExpired) as e:
            log("エラー: ASC からの取得に失敗しました（%s）" % type(e).__name__)
            status = 1

    rows = build_daily(raw_dir, read_daily(daily_path))
    if a.print_weekly is not None:
        sys.stdout.write(weekly_report(rows, a.print_weekly, ga4))
        return 0
    if rows:
        write_daily(daily_path, rows)
        log("daily.csv: %d 日分（%s〜%s）" % (len(rows), rows[0]["date"], rows[-1]["date"]))

    # 月曜に限らず毎回、直近に終わった週が未投稿なら投稿する（通常は月曜に投稿され、以降の日は控えで素通り）
    if not a.no_weekly:
        try:
            post_weekly(rows, last_complete_week_start(today), os.path.join(a.out_dir, "weekly-posted.txt"), ga4)
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
            log("エラー: %s" % e)
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
