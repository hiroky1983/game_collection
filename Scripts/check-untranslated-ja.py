#!/usr/bin/env python3
"""訳し漏れの機械チェック（多言語⑥ #2169）。

App/ と Packages/GameKit/Sources/ の Swift ソースから、日本語を含む文字列リテラルのうち
文言の表（`tr("…")`）を通していないものを洗い出す。あわせて、`tr("…")` のキーが
そのモジュールの `Localizable.xcstrings` に英語の訳つきで載っているかも確かめる
（`LocalizationCatalogTests` と同じ規則。Xcode の無い環境でも回せるように同じことをここでもやる）。

使い方:
    python3 Scripts/check-untranslated-ja.py            # 残りを表示。残りがあれば終了コード 1
    python3 Scripts/check-untranslated-ja.py --summary  # ファイルごとの件数だけ
    python3 Scripts/check-untranslated-ja.py --include-in-progress   # 「担当中」の範囲も数える
    python3 Scripts/check-untranslated-ja.py --root <dir>            # 別のツリーを調べる（テスト用）

数えないもの:
- コメントの中の日本語。
- `tr("…")` の第 1 引数（表のキー）。
- 開発者にしか見えない文: `precondition` / `assert` / `fatalError` / `print` / `debugDescription:` などの引数、
  `#Preview { … }` の中。
- 行末（または直前の行）に `// i18n-keep: 理由` と書いた行。「訳さない」と明示したもの（カードしりとりの単語、
  旧データの読み替えに使う保存済みの文字列など）。理由は必ず書く。
- `Scripts/i18n-check-exclusions.txt` に書いた範囲。
  - `keep <glob> <理由>`: ファイルごと訳さない（デバッグ用の画面など）。
  - `in-progress <glob> <issue> <メモ>`: 別の issue が担当中の範囲。既定では数えず、件数だけ別に出す。
    担当の PR がマージされたら、その行を消して残りゼロを確かめる。
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
from dataclasses import dataclass, field

JAPANESE = re.compile(r"[\u3040-\u30ff\u4e00-\u9fff\uff01-\uff5e]")
# 開発者向けの文（ユーザーには出ない）。リテラルの直前（同じ文の中）にこれがあれば数えない。
DEVELOPER_CALLS = re.compile(
    r"\b(precondition|preconditionFailure|assert|assertionFailure|fatalError|print|debugPrint|dump|"
    r"debugDescription|NSLog|os_log|Logger|logger\.\w+|log\.\w+|#expect|#require|Issue\.record)\b\s*[(:]"
)
KEEP_MARK = "i18n-keep"
INTERP = "\x00"  # リテラルの中の補間 \(…) の跡
SPECIFIER = re.compile(r"%(?:(\d+)\$)?(@|lld|ld|d|f|\.\d+f|s|%)")
TR_CALL = re.compile(r"(?<![A-Za-z0-9_])(?:[A-Za-z_][A-Za-z0-9_]*\.)?tr\(\s*$")


@dataclass
class Literal:
    path: str
    line: int
    text: str  # リテラルの中身（エスケープはそのまま）
    keyed: bool  # tr( の第 1 引数か


@dataclass
class Report:
    untranslated: list = field(default_factory=list)
    in_progress: dict = field(default_factory=dict)  # issue -> 件数
    kept: int = 0
    catalog_errors: list = field(default_factory=list)


def scan_swift(path: str, code: str):
    """Swift のソースを 1 回なめて、(リテラル, そのリテラルが始まる前の同じ文の文字列) を返す。

    コメント・文字列（複数行・補間の入れ子を含む）を区別する小さな字句解析。
    """
    out = []
    i, n, line = 0, len(code), 1
    stripped = []  # コメントを抜いたコード（tr( の判定に使う）

    def read_string(i, line, multiline, raw_hashes):
        """i は開きの引用符の直後。中身と閉じの直後の位置を返す。補間の中の文字列も読み飛ばす。"""
        start = i
        own = []  # 補間を除いた、リテラル自身の文字
        close = '"""' if multiline else '"'
        close += "#" * raw_hashes
        interp = "\\" + "#" * raw_hashes + "("
        nested = []
        while i < n:
            if code.startswith(close, i):
                return "".join(own), i + len(close), line, nested
            if code.startswith(interp, i):
                # 補間 \( … ) の中はコード。括弧の深さを数え、中の文字列も読む。
                j = i + len(interp)
                depth = 1
                while j < n and depth > 0:
                    c = code[j]
                    if c == "\n":
                        line += 1
                    if c == '"':
                        ml = code.startswith('"""', j)
                        inner, j, line, inner_nested = read_string(j + (3 if ml else 1), line, ml, 0)
                        nested.append((inner, line))
                        nested.extend(inner_nested)
                        continue
                    if c == "(":
                        depth += 1
                    elif c == ")":
                        depth -= 1
                    j += 1
                own.append(INTERP)
                i = j
                continue
            c = code[i]
            if c == "\\" and raw_hashes == 0:
                own.append(code[i:i + 2])
                i += 2
                continue
            if c == "\n":
                line += 1
                if not multiline:
                    return "".join(own), i, line, nested
            own.append(c)
            i += 1
        return "".join(own), i, line, nested

    while i < n:
        if code.startswith("//", i):
            j = code.find("\n", i)
            j = n if j < 0 else j
            i = j
            continue
        if code.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if code.startswith("/*", j):
                    depth += 1
                    j += 2
                elif code.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    if code[j] == "\n":
                        line += 1
                    j += 1
            i = j
            continue
        raw = 0
        if code[i] == "#":
            k = i
            while k < n and code[k] == "#":
                k += 1
            if k < n and code[k] == '"':
                raw = k - i
                i = k
        if code[i] == '"':
            multiline = code.startswith('"""', i)
            begin_line = line
            prefix = "".join(stripped[-400:])
            text, j, line, nested = read_string(i + (3 if multiline else 1), line, multiline, raw)
            keyed = bool(TR_CALL.search(prefix))
            out.append((Literal(path, begin_line, text, keyed), prefix))
            for inner, inner_line in nested:
                # 補間の中の文字列は、外側と同じ文に属する。
                out.append((Literal(path, inner_line, inner, False), prefix))
            stripped.append('""')
            i = j
            continue
        if code[i] == "\n":
            line += 1
        stripped.append(code[i])
        i += 1
    return out


def preview_ranges(code: str):
    """`#Preview` の `{ … }` が占める行の範囲。"""
    ranges = []
    for m in re.finditer(r"#Preview\b[^{]*\{", code):
        depth, j = 1, m.end()
        while j < len(code) and depth:
            if code[j] == "{":
                depth += 1
            elif code[j] == "}":
                depth -= 1
            j += 1
        ranges.append((code.count("\n", 0, m.start()) + 1, code.count("\n", 0, j) + 1))
    return ranges


def load_exclusions(path: str):
    """`#` で始まる行はコメント。それ以外は空白区切りの欄（行の途中のコメントは書かない）。"""
    keep, in_progress = [], []
    if not os.path.exists(path):
        return keep, in_progress
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if parts[0] == "keep" and len(parts) >= 2:
                keep.append(parts[1])
            elif parts[0] == "in-progress" and len(parts) >= 3:
                in_progress.append((parts[1], parts[2]))
            else:
                raise SystemExit(f"{path}: 読めない行: {line}")
    return keep, in_progress


def statement_tail(prefix: str) -> str:
    """リテラルの直前の、同じ文に属すると見なす部分（直近の改行以降。行をまたぐ呼び出しは 1 行前まで）。"""
    lines = prefix.split("\n")
    return "\n".join(lines[-2:])


def module_of(rel: str):
    parts = rel.split("/")
    if parts[0] == "App":
        return "App"
    if len(parts) > 3 and parts[:3] == ["Packages", "GameKit", "Sources"]:
        return parts[3]
    return None


def catalog_path(root: str, module: str) -> str:
    if module == "App":
        return os.path.join(root, "App/Localization/Localizable.xcstrings")
    return os.path.join(root, "Packages/GameKit/Sources", module, "Resources/Localization/Localizable.xcstrings")


def specifiers(text: str):
    found, index = [], 0
    for m in SPECIFIER.finditer(text):
        if m.group(2) == "%":
            continue
        index += 1
        found.append((int(m.group(1)) if m.group(1) else index, m.group(2)))
    return [t for _, t in sorted(found)]


def unescape(literal: str) -> str:
    out, it = [], iter(literal)
    for c in it:
        if c != "\\":
            out.append(c)
            continue
        nxt = next(it, "")
        out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, "\\" + nxt))
    return "".join(out)


def english_forms(entry):
    en = (entry.get("localizations") or {}).get("en")
    if not en:
        return None
    if "stringUnit" in en:
        return [en["stringUnit"].get("value", "")]
    plural = (en.get("variations") or {}).get("plural") or {}
    return [v.get("stringUnit", {}).get("value", "") for v in plural.values()]


def check(root: str, include_in_progress: bool) -> Report:
    report = Report()
    keep_globs, in_progress = load_exclusions(os.path.join(root, "Scripts/i18n-check-exclusions.txt"))
    keys_by_module: dict[str, set] = {}
    targets = [os.path.join(root, "App"), os.path.join(root, "Packages/GameKit/Sources")]
    for base in targets:
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(d for d in dirnames if d != "Resources" and not d.startswith("."))
            for name in sorted(filenames):
                if not name.endswith(".swift"):
                    continue
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, root)
                module = module_of(rel)
                if module == "CoreTestSupport":
                    continue
                with open(full, encoding="utf-8") as f:
                    code = f.read()
                lines = code.split("\n")
                previews = preview_ranges(code)
                owner = next((issue for glob, issue in in_progress if fnmatch.fnmatch(rel, glob)), None)
                file_kept = any(fnmatch.fnmatch(rel, g) for g in keep_globs)
                for lit, prefix in scan_swift(rel, code):
                    if lit.keyed:
                        keys_by_module.setdefault(module, set()).add(unescape(lit.text))
                        continue
                    if not JAPANESE.search(lit.text):
                        continue
                    if any(a <= lit.line <= b for a, b in previews):
                        continue
                    if DEVELOPER_CALLS.search(statement_tail(prefix)):
                        continue
                    here = lines[lit.line - 1] if lit.line - 1 < len(lines) else ""
                    above = lines[lit.line - 2] if lit.line >= 2 else ""
                    if file_kept or KEEP_MARK in here or above.strip().startswith("// " + KEEP_MARK):
                        report.kept += 1
                        continue
                    if owner and not include_in_progress:
                        report.in_progress[owner] = report.in_progress.get(owner, 0) + 1
                        continue
                    report.untranslated.append(lit)
    # 表の検査（tr のキーが表にあり、英語の訳があり、日本語が残らず、書式が一致する）。
    modules = set(keys_by_module) | {"App"}
    sources = os.path.join(root, "Packages/GameKit/Sources")
    if os.path.isdir(sources):
        modules |= {m for m in os.listdir(sources) if os.path.exists(catalog_path(root, m))}
    for module in sorted(modules):
        keys = keys_by_module.get(module, set())
        path = catalog_path(root, module)
        try:
            with open(path, encoding="utf-8") as f:
                strings = json.load(f).get("strings", {})
        except (OSError, ValueError) as e:
            report.catalog_errors.append(f"{module}: 表が読めない ({e})")
            continue
        for key in sorted(keys):
            if INTERP in key:
                report.catalog_errors.append(f"{module}: 「{key.replace(INTERP, chr(92) + '(…)')}」はキーに文字列補間を使っている")
                continue
            if key not in strings:
                report.catalog_errors.append(f"{module}: 「{key}」が表に無い")
        for key, entry in sorted(strings.items()):
            forms = english_forms(entry)
            if forms is None:
                report.catalog_errors.append(f"{module}: 「{key}」に英語の訳が無い")
                continue
            for form in forms:
                if not form.strip() and key.strip():
                    report.catalog_errors.append(f"{module}: 「{key}」の英語が空")
                if JAPANESE.search(form):
                    report.catalog_errors.append(f"{module}: 「{key}」の英語に日本語が残っている: {form}")
                if specifiers(form) != specifiers(key):
                    report.catalog_errors.append(f"{module}: 「{key}」と英語「{form}」で書式指定が食い違う")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    parser.add_argument("--summary", action="store_true", help="ファイルごとの件数だけ出す")
    parser.add_argument("--include-in-progress", action="store_true", help="担当中の範囲も残りとして数える")
    args = parser.parse_args()

    report = check(args.root, args.include_in_progress)
    by_file: dict[str, list] = {}
    for lit in report.untranslated:
        by_file.setdefault(lit.path, []).append(lit)
    for path, lits in by_file.items():
        if args.summary:
            print(f"{len(lits):5d}  {path}")
            continue
        for lit in lits:
            first = lit.text.replace(INTERP, "\\(…)").split("\\n")[0].split("\n")[0]
            print(f"{path}:{lit.line}: \"{first[:80]}\"")
    for error in report.catalog_errors:
        print(f"表: {error}")

    print()
    print(f"訳し漏れ（表を通していない日本語）: {len(report.untranslated)} 件")
    print(f"訳さないと明示（i18n-keep / keep）: {report.kept} 件")
    if report.in_progress:
        detail = "・".join(f"{issue} {count} 件" for issue, count in sorted(report.in_progress.items()))
        print(f"担当中として除外: {sum(report.in_progress.values())} 件（{detail}）")
    print(f"表の不備: {len(report.catalog_errors)} 件")
    return 1 if report.untranslated or report.catalog_errors else 0


if __name__ == "__main__":
    sys.exit(main())
