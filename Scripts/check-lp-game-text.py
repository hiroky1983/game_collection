#!/usr/bin/env python3
"""LP（web/app/lib/games.ts）の1行紹介が、アプリの GameModule.description と一致するか確認する（#2941）。

なぜ要るか: games.ts は「アプリ内の GameModule.description に合わせる」と書いているが、守りが人手だけで、
チャリンコおじさんは LP の中で ja が「30 ステージ」・taglineEn が「42 stages」と食い違い、アプリ（42）とも
合っていなかった。slug の並びは Scripts/check-lp-game-list.sh が見るが、文言は誰も見ていなかった。

何と比べるか（アプリ側を正とする）:
  ja: Packages/GameKit/Sources/<Target>/<Xxx>Module.swift の `description` の `tr("…")`
  en: 同じ Target の Resources/Localization/Localizable.xcstrings の、その ja 文言に対する `en` 値
  LP: games.ts の `tagline`（ja）と `taglineEn`（en）。slug は Module の `id` で引く
      （LP の slug が id と違う麻雀ソリティアは SLUG_ALIAS で対応）

LP に載っているが Module が見つからないゲーム（comingSoon の未リリース分など）は照合対象外。

使い方: python3 Scripts/check-lp-game-text.py [games.ts のパス] [Sources のパス]
終了コード: 0 = 一致 / 1 = 食い違い or 読み取り失敗
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# LP の slug がアプリの id と意図的に違うもの（check-lp-game-list.sh の lp_slug_for と同じ）
SLUG_ALIAS = {"mahjong": "mahjong-solitaire"}

# 文言を意図的に変えているもの。(slug, "ja" | "en") → 理由。理由の無い追加は禁止
# （LP は検索の入口なので、アプリの1行より長く書きたい事情があるときだけここに足す）。
ALLOW = {}


def ts_string(src, start):
    """src[start] が `"` の位置から TypeScript の文字列リテラルを読む。"""
    assert src[start] == '"'
    out = []
    i = start + 1
    while src[i] != '"':
        if src[i] == "\\":
            i += 1
            out.append({"n": "\n", "t": "\t"}.get(src[i], src[i]))
        else:
            out.append(src[i])
        i += 1
    return "".join(out)


def read_lp(path):
    """games.ts から slug → {tagline, taglineEn} を取る。エントリは2スペースの `{` で始まる。"""
    src = path.read_text(encoding="utf-8")
    entries = {}
    for block in re.split(r"(?m)^  \{\n", src)[1:]:
        fields = {}
        for key in ("slug", "tagline", "taglineEn"):
            m = re.search(r'(?m)^    %s:\s*(?=")' % key, block)
            if m:
                fields[key] = ts_string(block, m.end())
        if "slug" in fields:
            entries[fields["slug"]] = fields
    return entries


def read_modules(sources):
    """Module.swift から id → (ja description, xcstrings のパス)。"""
    modules = {}
    for f in sorted(sources.glob("*/*Module.swift")):
        text = f.read_text(encoding="utf-8")
        mid = re.search(r'(?m)^\s*public let id = "([^"]*)"', text)
        desc = re.search(r'var description: String \{ tr\("((?:[^"\\]|\\.)*)"\) \}', text)
        if not mid or not desc:
            continue
        ja = ts_string('"' + desc.group(1) + '"', 0)
        modules[mid.group(1)] = (ja, f.parent / "Resources/Localization/Localizable.xcstrings", f.name)
    return modules


def main():
    games = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "web/app/lib/games.ts"
    sources = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "Packages/GameKit/Sources"
    lp = read_lp(games)
    modules = read_modules(sources)
    if not lp or not modules:
        print("check-lp-game-text: LP か Module から読み取れませんでした", file=sys.stderr)
        return 1

    problems = []
    checked = 0
    for mid, (ja, xc, fname) in modules.items():
        slug = SLUG_ALIAS.get(mid, mid)
        entry = lp.get(slug)
        if entry is None:
            continue
        checked += 1
        if (slug, "ja") not in ALLOW and entry.get("tagline") != ja:
            problems.append((slug, "ja", fname, ja, entry.get("tagline")))
        if (slug, "en") in ALLOW:
            continue
        try:
            strings = json.loads(xc.read_text(encoding="utf-8"))["strings"]
            en = strings[ja]["localizations"]["en"]["stringUnit"]["value"]
        except (OSError, KeyError, ValueError):
            problems.append((slug, "en", fname, "(xcstrings から英訳を読めません: %s)" % xc, entry.get("taglineEn")))
            continue
        if entry.get("taglineEn") != en:
            problems.append((slug, "en", fname, en, entry.get("taglineEn")))

    if checked == 0:
        print("check-lp-game-text: 照合できたゲームが0本です（読み取り方が壊れている）", file=sys.stderr)
        return 1
    if not problems:
        print("check-lp-game-text: OK（%d本の tagline / taglineEn がアプリの文言と一致）" % checked)
        return 0

    print("check-lp-game-text: LP の1行紹介がアプリの文言と一致しません（アプリ側が正）", file=sys.stderr)
    for slug, lang, fname, app, lpv in problems:
        print("  [%s] %s" % (slug, lang), file=sys.stderr)
        print("    アプリ(%s): %s" % (fname, app), file=sys.stderr)
        print("    LP        : %s" % lpv, file=sys.stderr)
    print("\nLP を直すか、意図した差なら ALLOW に理由付きで足してください（#2941）。", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
