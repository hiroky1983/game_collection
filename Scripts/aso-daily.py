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

API は GET だけを使う。リクエストが無い・止まっている場合は作り直さずにエラー終了する
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


def weekly_report(rows, week_start):
    """week_start（月曜）から 7 日間を「前週」とした週次コメントの本文（Markdown）。"""
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


def post_weekly(rows, week_start, state_path):
    """week_start の週を投稿する。投稿済み（控え or Issue のコメントに印がある）なら何もしない。"""
    if week_start.isoformat() in _posted_local(state_path):
        return None
    if already_posted(weekly_marker(week_start)):
        log("週次: %s の週は投稿済みのため見送り" % week_start.isoformat())
        _mark_posted(state_path, week_start)
        return None
    body = weekly_report(rows, week_start)
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

    status = 0
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
        sys.stdout.write(weekly_report(rows, a.print_weekly))
        return 0
    if rows:
        write_daily(daily_path, rows)
        log("daily.csv: %d 日分（%s〜%s）" % (len(rows), rows[0]["date"], rows[-1]["date"]))

    # 月曜に限らず毎回、直近に終わった週が未投稿なら投稿する（通常は月曜に投稿され、以降の日は控えで素通り）
    if not a.no_weekly:
        try:
            post_weekly(rows, last_complete_week_start(today), os.path.join(a.out_dir, "weekly-posted.txt"))
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
            log("エラー: %s" % e)
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
