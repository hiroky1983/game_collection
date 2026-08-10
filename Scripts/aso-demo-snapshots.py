#!/usr/bin/env python3
"""App Store スクリーンショット用のデモ状態（中断スナップショット）を生成する。

各ゲームの View は「セーブが無いとき」だけ設定シートを出す実装になっているため、
スナップショットを置くことでシートを出さずに、狙った盤面をそのまま撮影できる
（= シミュレータへのタップ操作が不要になる）。JSON の形は Packages/GameKit の
各 *Snapshot 型に合わせてある。

使い方: python3 Scripts/aso-demo-snapshots.py <出力ディレクトリ>
出力: <出力ディレクトリ>/<gameID>.json （FileSnapshotStore と同じ命名）
"""

import json
import os
import random
import sys

# JSONEncoder の既定（.deferredToDate）に合わせ、2001-01-01 起点の秒数で渡す。
# 表示には使われないため固定値でよい（撮影結果を決定的にするため固定する）。
STARTED_AT = 800000000.0


def snapshot_2048():
    """1024 タイルまで育った盤面。「記録更新に夢中」の訴求に使う。"""
    return {
        "board": [
            [1024, 512, 64, 8],
            [256, 128, 32, 4],
            [16, 8, 4, 2],
            [8, 4, 2, 0],
        ],
        "score": 12456,
    }


def snapshot_shogi():
    """平手から飛車先の歩を交換した序盤〜中盤。10手目で先手（人間）の手番。

    手番を人間側に置くのが重要で、CPU の手番のまま撮ると ShogiView の
    `.task(id: model.moves.count)` が発火して撮影中に AI が指してしまう。
    """
    return {
        "initialSfen": "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1",
        "moves": [
            "7g7f", "3c3d",
            "2g2f", "8c8d",
            "2f2e", "8d8e",
            "2e2d", "2c2d",
            "2h2d", "8e8f",
        ],
        "phase": "playing",
        "reviewPly": None,
        "sente": "human",
        "gote": "ai",
        "aiLevel": 1,
        "startedAt": STARTED_AT,
        "undoUsed": False,
        "resigned": False,
    }


def snapshot_gomoku():
    """中央付近で競り合っている中盤。黒（人間）の手番で止める。"""
    history = [
        (7, 7, 0), (7, 8, 1),
        (8, 8, 0), (6, 8, 1),
        (8, 6, 0), (9, 9, 1),
        (6, 6, 0), (5, 7, 1),
    ]
    return {
        "cells": [None] * (15 * 15),  # moveHistory から再構築されるため未使用
        "currentStone": 0,
        "humanSide": 0,
        "aiLevel": 1,
        "startedAt": STARTED_AT,
        "moveHistory": [{"row": r, "col": c, "stone": s} for r, c, s in history],
        "undoUsed": False,
        "resigned": False,
        "winner": None,
    }


def _othello_flips(cells, row, col, stone):
    """(row, col) に stone を置いたときに返る石の座標。"""
    flips = []
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            if dr == 0 and dc == 0:
                continue
            line, r, c = [], row + dr, col + dc
            while 0 <= r < 8 and 0 <= c < 8 and cells[r * 8 + c] == 1 - stone:
                line.append((r, c))
                r, c = r + dr, c + dc
            if line and 0 <= r < 8 and 0 <= c < 8 and cells[r * 8 + c] == stone:
                flips += line
    return flips


def snapshot_othello():
    """実際のルールで 20 手進めた本物の中盤局面（黒 = 人間の手番で止める）。

    盤面を手で作ると「ありえない配置」になるため、貪欲 AI 同士で対局させて
    到達可能な局面だけを使う。
    """
    cells = [None] * 64
    cells[3 * 8 + 3] = 1
    cells[3 * 8 + 4] = 0
    cells[4 * 8 + 3] = 0
    cells[4 * 8 + 4] = 1

    stone = 0  # 黒先
    for _ in range(20):
        moves = []
        for i in range(64):
            if cells[i] is not None:
                continue
            f = _othello_flips(cells, i // 8, i % 8, stone)
            if f:
                moves.append((len(f), i, f))
        if not moves:  # パスしか無ければ手番を渡す
            stone = 1 - stone
            continue
        moves.sort(key=lambda m: (-m[0], m[1]))  # 最大取り（決定的）
        _, idx, flips = moves[0]
        cells[idx] = stone
        for r, c in flips:
            cells[r * 8 + c] = stone
        stone = 1 - stone

    assert stone == 0, "黒（人間）の手番で止められなかった"
    return {
        "cells": cells,
        "currentStone": 0,
        "humanSide": 0,
        "aiLevel": 1,
        "startedAt": STARTED_AT,
        "winner": None,
        "isDraw": False,
        "mustPass": False,
        "turnID": 0,
        "undoUsed": False,
    }


def snapshot_minesweeper():
    """9x9・地雷10個の進行中の盤面。数字が開いた状態を撮るため実際に開いて作る。"""
    rows, cols = 9, 9
    mines = [(0, 5), (1, 2), (2, 7), (3, 3), (4, 6), (5, 1), (6, 4), (7, 8), (8, 0), (8, 6)]
    mine_set = set(mines)

    def adjacent(r, c):
        return sum(
            1
            for dr in (-1, 0, 1)
            for dc in (-1, 0, 1)
            if (dr or dc) and (r + dr, c + dc) in mine_set
        )

    revealed = set()

    def flood(r, c):
        """0 のマスから連鎖的に開く（アプリ側の開示ロジックと同じ挙動）。"""
        stack = [(r, c)]
        while stack:
            cr, cc = stack.pop()
            if not (0 <= cr < rows and 0 <= cc < cols) or (cr, cc) in revealed:
                continue
            if (cr, cc) in mine_set:
                continue
            revealed.add((cr, cc))
            if adjacent(cr, cc) == 0:
                for dr in (-1, 0, 1):
                    for dc in (-1, 0, 1):
                        if dr or dc:
                            stack.append((cr + dr, cc + dc))

    flood(0, 0)
    flood(6, 1)
    flood(2, 4)

    # 開いた領域の周りを2巡だけ広げて「中盤らしい開き具合」にする（勝利状態にはしない）
    for _ in range(2):
        frontier = {
            (r + dr, c + dc)
            for r, c in revealed
            for dr in (-1, 0, 1)
            for dc in (-1, 0, 1)
        }
        for r, c in sorted(frontier):
            if 0 <= r < rows and 0 <= c < cols and (r, c) not in mine_set:
                revealed.add((r, c))
    assert len(revealed) < rows * cols - len(mine_set), "全マス開放（勝利）状態になっている"

    flags = [(1, 2), (3, 3)]  # 見抜いた地雷に旗を立てた状態
    cells = [
        [
            {
                "isRevealed": (r, c) in revealed,
                "isFlagged": (r, c) in flags,
                "isMine": (r, c) in mine_set,
                "adjacentMines": adjacent(r, c),
                "isContinuedMine": False,
            }
            for c in range(cols)
        ]
        for r in range(rows)
    ]
    assert not (revealed & mine_set), "地雷を開いた状態になっている"
    return {
        "rows": rows,
        "cols": cols,
        "totalMines": len(mines),
        "cells": cells,
        "flagCount": len(flags),
        "revealedCount": len(revealed),
        "elapsedSeconds": 47,
    }


def _card(suit, rank, offset):
    """id は 0-51 で一意になるように suit/rank から決める。"""
    return {"id": suit * 13 + offset, "suit": suit, "rank": rank}


def snapshot_poker():
    """カード交換フェーズ（5カードドローの見せ場）。CPU の手札は伏せられたまま。

    アプリが実際に保存するのは betting1/exchange/cpuExchange/betting2 の4フェーズだけなので、
    撮影用の状態もその中から選ぶ（result を注入すると役名の表示だけが復元されず矛盾する）。
    """
    player = [_card(0, 12, 10), _card(1, 12, 10), _card(2, 12, 10), _card(3, 8, 6), _card(0, 5, 3)]
    cpu = [_card(1, 14, 12), _card(2, 14, 12), _card(3, 9, 7), _card(0, 9, 7), _card(1, 4, 2)]
    used = {(c["suit"], c["rank"]) for c in player + cpu}
    deck = [
        _card(s, r, r - 2)
        for s in range(4)
        for r in range(2, 15)
        if (s, r) not in used
    ]
    return {
        "playerHand": player,
        "cpuHand": cpu,
        "deck": deck,
        "playerChips": 90,   # 初期100枚からアンティ10枚ずつ（= ポット20枚）
        "cpuChips": 90,
        "pot": 20,
        "phase": "exchange",
        "currentBet": 0,
        "playerBetInRound": 0,
        "cpuBetInRound": 0,
        "cpuFolded": False,
        "cpuAction": "",
    }


def snapshot_blackjack():
    """プレイヤーの手番（ディーラーの2枚目は伏せられた状態）。"""
    player = [{"id": 9, "suit": 0, "rank": 10}, {"id": 19, "suit": 1, "rank": 7}]
    dealer = [{"id": 38, "suit": 2, "rank": 13}, {"id": 4, "suit": 3, "rank": 5}]
    used = {(c["suit"], c["rank"]) for c in player + dealer}
    deck = [
        {"id": s * 13 + r - 1, "suit": s, "rank": r}
        for s in range(4)
        for r in range(1, 14)
        if (s, r) not in used
    ]
    return {
        "playerHand": player,
        "dealerHand": dealer,
        "deck": deck,
        "chips": 950,
        "bet": 50,
        "phase": "playerTurn",
    }


def snapshot_concentration():
    """12ペア中4ペアが取れた状態。マッチ済みカードは常に表向きで描画される。

    ミスマッチで開いたままの2枚はロード時に裏返される仕様なので再現しない。
    """
    pairs = ["🍎", "🍊", "🍋", "🍇", "🍓", "🍒", "🍑", "🥝", "🌸", "🌻", "🌈", "⭐"]
    # 同じ絵柄が隣り合わないよう、固定シードでシャッフルした配置にする
    # （ペアが並んでいると実際の対局ではありえない絵になる）
    positions = list(range(24))
    random.Random(7).shuffle(positions)
    symbols = [""] * 24
    for i, symbol in enumerate(pairs):
        symbols[positions[2 * i]] = symbol
        symbols[positions[2 * i + 1]] = symbol
    matched_pairs = {pairs[i] for i in (2, 5, 8, 11)}  # 4ペアが取れている（3対1）
    is_matched = [s in matched_pairs for s in symbols]
    return {
        "symbols": symbols,
        "isFaceUp": list(is_matched),
        "isMatched": is_matched,
        "currentPlayer": 0,
        "playerScore": 3,
        "cpuScore": 1,
        "pairCount": 12,
        "cpuLevel": 1,
        "mattaUsed": False,
    }


SNAPSHOTS = {
    "2048": snapshot_2048,
    "shogi": snapshot_shogi,
    "gomoku": snapshot_gomoku,
    "othello": snapshot_othello,
    "minesweeper": snapshot_minesweeper,
    "poker": snapshot_poker,
    "blackjack": snapshot_blackjack,
    "concentration": snapshot_concentration,
}


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for game_id, build in SNAPSHOTS.items():
        path = os.path.join(out, f"{game_id}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(build(), f, ensure_ascii=False)
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
