#!/usr/bin/env python3
"""変更ファイルから、走らせる GameKit のテストターゲットを選ぶ（#2953）。

標準入力: 変更ファイルのリポジトリ相対パス（1 行 1 件）
標準出力（1 行）:
  all            全テストを回す
  none           GameKit のテストに関係する変更が無い
  ^(A|B)\\.      `swift test --filter` に渡す正規表現（影響を受けるテストターゲットの和）

選び方（層を手で書かない。ゲームを足しても設定は要らない）:
  1. 変更ファイル → 所属ターゲット（Package.swift の path。省略時は Sources/<名前>・Tests/<名前>）
  2. ターゲット間の「使う」辺を逆にたどり、影響を受けるテストターゲットを集める
     辺 = Package.swift の dependencies
          + テストターゲットのソースに別ターゲット名が語として現れるもの（`Sources/GameX/…` を読む走査テスト）
          + ソース全体を舐める走査テスト（Sources を丸ごと列挙するもの）は全ターゲットへ辺を張る
  3. App/ Config/ project.yml Package.swift CI 設定など、全体に効く変更は all

使い方:
  git diff --name-only HEAD^1 HEAD | python3 Scripts/select-gamekit-tests.py
  --root DIR           リポジトリのルート（既定: このスクリプトの 1 つ上）
  --package-json FILE  `swift package dump-package` の出力（既定: swift を呼ぶ。テスト用）
  --explain            選んだ理由を標準エラーへ出す
"""
import argparse
import json
import os
import re
import subprocess
import sys

PACKAGE_DIR = "Packages/GameKit"

# これらの変更は全部のテストを回す。アプリ本体・依存の版・CI の定義・この選別自身。
ALL_PREFIXES = ("App/", "Config/", ".github/workflows/ci.yml")
ALL_FILES = {"project.yml", "Scripts/select-gamekit-tests.py"}

# ソース全体を舐める走査テストの目印（Sources の根を取って、さらに下へ名指しで降りないもの）。
# どのモジュールの変更でも影響を受ける。名指し（`Sources/GameX`）で読むものは、ターゲット名の語の一致で拾う。
SCAN_ALL = re.compile(r'appendingPathComponent\("Sources"\)(?!\s*\.appendingPathComponent)')


def load_package(root, package_json):
    if package_json:
        with open(package_json, encoding="utf-8") as f:
            return json.load(f)
    out = subprocess.run(["swift", "package", "dump-package", "--package-path", os.path.join(root, PACKAGE_DIR)],
                         check=True, capture_output=True, text=True).stdout
    return json.loads(out[out.index("{"):])


def dep_names(target):
    names = []
    for d in target.get("dependencies", []):
        for kind, args in d.items():
            if kind == "byName":
                names.append(args[0])
            elif kind == "target":
                names.append(args[0])
    return names


def swift_text(directory):
    chunks = []
    for base, _, files in os.walk(directory):
        for name in files:
            if name.endswith(".swift"):
                with open(os.path.join(base, name), encoding="utf-8", errors="replace") as f:
                    chunks.append(f.read())
    return "\n".join(chunks)


def build_graph(root, package):
    targets = package["targets"]
    paths = {}
    is_test = {}
    for t in targets:
        test = t["type"] == "test"
        is_test[t["name"]] = test
        paths[t["name"]] = t.get("path") or (("Tests/" if test else "Sources/") + t["name"])
    names = set(paths)
    uses = {n: set() for n in names}  # n が使う（n の変更の影響を受ける側 → 使われる側の逆引きに使う）
    for t in targets:
        uses[t["name"]].update(d for d in dep_names(t) if d in names)
    reasons = {}
    for n in names:
        if not is_test[n]:
            continue
        text = swift_text(os.path.join(root, PACKAGE_DIR, paths[n]))
        if SCAN_ALL.search(text):
            extra = {w for w in names if not is_test[w]}
            reasons[n] = "ソース全体を走査"
        else:
            extra = {w for w in names - {n} if re.search(r"\b" + re.escape(w) + r"\b", text)}
        uses[n].update(extra)
    return paths, is_test, uses, reasons


def owner(rel_in_package, paths):
    best = None
    for name, p in paths.items():
        if rel_in_package == p or rel_in_package.startswith(p + "/"):
            if best is None or len(p) > len(paths[best]):
                best = name
    return best


def select(files, root, package):
    paths, is_test, uses, _ = build_graph(root, package)
    changed = set()
    for f in files:
        f = f.strip()
        if not f:
            continue
        if f in ALL_FILES or f.startswith(ALL_PREFIXES):
            return "all", "全体に効く変更: " + f
        if f.startswith(PACKAGE_DIR + "/"):
            name = owner(f[len(PACKAGE_DIR) + 1:], paths)
            if name is None:
                return "all", "ターゲットに属さない Packages の変更: " + f
            changed.add(name)
    if not changed:
        return "none", "GameKit に関係する変更なし"
    # 変更したターゲットを（直接・間接に）使うターゲットを集める。テストは行き止まり（テストを使うテストは無い）
    # ので、たどるのは非テストだけ。テスト同士の言及（別のテストのディレクトリを読む等）は直接の辺として扱う。
    affected = set(changed)
    grew = True
    while grew:
        grew = False
        for n, used in uses.items():
            if n not in affected and not is_test[n] and used & affected:
                affected.add(n)
                grew = True
    affected |= {n for n, used in uses.items() if is_test[n] and used & affected}
    tests = sorted(n for n in affected if is_test[n])
    if not tests:
        return "none", "変更したターゲット %s を使うテストが無い" % sorted(changed)
    return "^(" + "|".join(tests) + ")\\.", "変更: %s → テスト: %s" % (sorted(changed), tests)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    ap.add_argument("--package-json")
    ap.add_argument("--explain", action="store_true")
    args = ap.parse_args()
    root = os.path.abspath(args.root)
    result, why = select(sys.stdin.read().splitlines(), root, load_package(root, args.package_json))
    if args.explain:
        print(why, file=sys.stderr)
    print(result)


if __name__ == "__main__":
    main()
