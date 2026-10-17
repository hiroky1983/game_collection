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
    """中央付近で競り合っている中盤（16手）。黒（人間）の手番で止める。"""
    history = [
        (7, 7, 0), (7, 8, 1),
        (8, 8, 0), (6, 8, 1),
        (8, 6, 0), (9, 9, 1),
        (6, 6, 0), (5, 7, 1),
        (9, 5, 0), (6, 5, 1),
        (7, 5, 0), (8, 5, 1),
        (5, 9, 0), (6, 7, 1),
        (9, 7, 0), (10, 4, 1),
    ]

    # 実プレイで到達しうる棋譜であることの検査
    assert len({(r, c) for r, c, _ in history}) == len(history), "同じ交点に2回打っている"
    assert [s for _, _, s in history] == [i % 2 for i in range(len(history))], "手番が交互でない"
    board = {(r, c): s for r, c, s in history}
    for (r, c), stone in board.items():
        for dr, dc in ((0, 1), (1, 0), (1, 1), (1, -1)):
            run = 1
            for sign in (1, -1):
                nr, nc = r + dr * sign, c + dc * sign
                while board.get((nr, nc)) == stone:
                    run += 1
                    nr, nc = nr + dr * sign, nc + dc * sign
            assert run < 5, f"すでに5連ができている（{stone} at {r},{c}）= 終局後の盤面"

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
        "turnID": 20,  # 20手進めた局面なので実機と同じ値にする
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

    def click(r, c):
        """プレイヤーが1マス開ける操作。0 のマスなら連鎖、数字マスなら1マスだけ開く。

        「開いたマスを直接集合に足す」やり方だと *0 のマスの隣が閉じたまま* という
        実プレイでは起こり得ない盤面ができてしまう（アプリの `floodReveal` は 0 を開けたら
        必ず全隣接マスを開ける）。必ずこの関数経由で開けること。
        """
        if not (0 <= r < rows and 0 <= c < cols) or (r, c) in mine_set:
            return
        if adjacent(r, c) == 0:
            flood(r, c)
        else:
            revealed.add((r, c))

    click(0, 0)
    click(6, 1)
    click(2, 4)

    # 開いた領域のまわりを1巡ぶんクリックして「中盤らしい開き具合」にする
    # （2巡やるとほぼ解き終わった盤面になり、途中でやめた画に見えなくなる）
    frontier = sorted(
        {
            (r + dr, c + dc)
            for r, c in revealed
            for dr in (-1, 0, 1)
            for dc in (-1, 0, 1)
        }
        - revealed
    )
    for r, c in frontier:
        click(r, c)

    # 実プレイで到達しうる盤面であることの検査（0 のマスの隣は必ず開いている）
    for r, c in revealed:
        if adjacent(r, c) == 0:
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    nr, nc = r + dr, c + dc
                    if 0 <= nr < rows and 0 <= nc < cols and (nr, nc) not in mine_set:
                        assert (nr, nc) in revealed, f"0のマス({r},{c})の隣({nr},{nc})が閉じている"
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
        "cpuAction": "チェック",  # .exchange へは cpuBet1Response 経由でしか入らず、必ず表示が付く
    }


def snapshot_blackjack():
    """プレイヤーの手番（ディーラーの2枚目は伏せられた状態）。"""
    def bj_card(suit, rank):
        """id は BlackjackModel.makeDeck と同じ採番（suit*13 + rank - 1）にする。"""
        return {"id": suit * 13 + rank - 1, "suit": suit, "rank": rank}

    player = [bj_card(0, 10), bj_card(1, 7)]
    dealer = [bj_card(2, 13), bj_card(3, 5)]
    used = {(c["suit"], c["rank"]) for c in player + dealer}
    deck = [
        bj_card(s, r)
        for s in range(4)
        for r in range(1, 14)
        if (s, r) not in used
    ]
    ids = [c["id"] for c in player + dealer + deck]
    assert len(ids) == len(set(ids)) == 52, "カード id が重複または不足している"
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
    # 固定シードでシャッフルした配置にする（ペアが並んだ配置だと「取れたペアが
    # 隣同士に並ぶ」不自然な絵になるため。裏向きのカードの並びは絵に出ない）
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


def _sudoku_ok(grid, index, digit):
    """SudokuEngine.isValid と同じ判定（行・列・3x3 ブロックの衝突）。"""
    row, col = divmod(index, 9)
    for k in range(9):
        if grid[row * 9 + k] == digit or grid[k * 9 + col] == digit:
            return False
    br, bc = (row // 3) * 3, (col // 3) * 3
    for dr in range(3):
        for dc in range(3):
            if grid[(br + dr) * 9 + bc + dc] == digit:
                return False
    return True


def _sudoku_solution_count(grid, limit=2):
    """SudokuEngine.solutionCount と同じ（limit に達したら数えるのをやめる）。"""
    try:
        index = grid.index(0)
    except ValueError:
        return 1
    found = 0
    for digit in range(1, 10):
        if _sudoku_ok(grid, index, digit):
            grid[index] = digit
            found += _sudoku_solution_count(grid, limit)
            grid[index] = 0
            if found >= limit:
                break
    return found


def snapshot_sudoku():
    """「ふつう」を途中まで解いた盤面（ミス1回・ヒント1回使用）。

    出題は SudokuEngine.generate と同じ手順（完成盤を作り、唯一解を保てるマスだけ削る）で
    作るので、アプリが実際に配る問題と同じ性質になる。SudokuModel.isValid が
    「出題マスは正解と一致」「board != solution」「hintsUsed 0...3」「mistakes 0...3」まで
    見るので、どれかを外すと中断データごと捨てられて新規ゲームシートが出てしまう。
    mistakes を 3 にすると失敗オーバーレイが盤に被るので 3 未満にすること。
    """
    rng = random.Random(20260907)

    # 完成盤（パターン法 + 行・列・数字の入れ替え。どう並べ替えても数独の制約は保たれる）
    def pattern(r, c):
        return (3 * (r % 3) + r // 3 + c) % 9

    rows = [g * 3 + r for g in rng.sample(range(3), 3) for r in rng.sample(range(3), 3)]
    cols = [g * 3 + c for g in rng.sample(range(3), 3) for c in rng.sample(range(3), 3)]
    digits = rng.sample(range(1, 10), 9)
    solution = [digits[pattern(r, c)] for r in rows for c in cols]

    # 唯一解を保てるマスだけ削る（normal = 40〜45 マス）
    board = solution[:]
    target = rng.randint(40, 45)
    removed = 0
    for index in rng.sample(range(81), 81):
        if removed >= target:
            break
        backup = board[index]
        board[index] = 0
        if _sudoku_solution_count(board[:]) == 1:
            removed += 1
        else:
            board[index] = backup
    given = [v != 0 for v in board]

    # ここからプレイヤーの進捗。11マスを自力で、1マスをヒントで埋め、4マスにメモを残す。
    blanks = [i for i in range(81) if board[i] == 0]
    rng.shuffle(blanks)
    solved_by_player, hinted, noted = blanks[:11], blanks[11], blanks[12:16]
    for index in solved_by_player + [hinted]:
        board[index] = solution[index]
    notes = [0] * 81
    for index in noted:
        # 行・列・ブロックから絞った候補を3つだけ書いた状態（bit0 が 1、bit8 が 9）
        for digit in [d for d in range(1, 10) if _sudoku_ok(board, index, d)][:3]:
            notes[index] |= 1 << (digit - 1)

    assert board != solution, "完成済みは「プレイ中」として復元できない"
    assert all(not given[i] or board[i] == solution[i] for i in range(81)), "出題マスが正解と違う"
    assert all(board[i] in (0, solution[i]) for i in range(81)), "誤答が残っている（赤いマスになる）"
    return {
        "board": board,
        "given": given,
        "solution": solution,
        "notes": notes,
        "elapsedSeconds": 383,
        "hintsUsed": 1,  # hintedCells の枚数と必ず合わせる
        "difficulty": "normal",
        "hintedCells": [hinted],
        "mistakes": 1,
    }


# 34 種の並び（MahjongTileOrder と同じ: 萬1-9 → 筒1-9 → 索1-9 → 風 東南西北 → 三元 中發白）
_M_ORDER = (
    [("characters", n) for n in range(1, 10)]
    + [("circles", n) for n in range(1, 10)]
    + [("bamboos", n) for n in range(1, 10)]
    + [("wind", n) for n in range(4)]
    + [("dragon", n) for n in range(3)]
)
_M_INDEX = {tile: i for i, tile in enumerate(_M_ORDER)}


def _tile(tile):
    """MahjongTile の JSON 表現（自動合成の enum + associated value）。"""
    return {tile[0]: {"_0": tile[1]}}


def _hand(tiles):
    """MahjongHand は 34 種の枚数配列 1 本だけを持つ。"""
    counts = [0] * 34
    for tile in tiles:
        counts[_M_INDEX[tile]] += 1
    return {"counts": counts}


def snapshot_mahjong4():
    """東2局7巡目・自分の手番（聴牌して立直を打てる形）。

    CPU の手番のまま撮ると `.task(id: model.turnKey)` の `runCPUTurnsIfNeeded()` が
    走って打牌が進むため、`currentPlayer` は必ず人間（0）にする。立直中（`riichi[0]`）も
    自摸切りで自動進行するので false のままにする。`handResult` を入れると対局画面では
    なくリザルトカードになるので null。
    """
    m = lambda n: ("characters", n)   # noqa: E731 - 牌の並びを詰めて書くための別名
    p = lambda n: ("circles", n)      # noqa: E731
    s = lambda n: ("bamboos", n)      # noqa: E731
    w = lambda n: ("wind", n)         # noqa: E731 - 0=東 1=南 2=西 3=北
    d = lambda n: ("dragon", n)       # noqa: E731 - 0=中 1=發 2=白

    # 自分（0）は 234m 567m 345p 78p 東東 の13枚 = 6筒・9筒 待ちの聴牌。
    hands = [
        [m(2), m(3), m(4), m(5), m(6), m(7), p(3), p(4), p(5), p(7), p(8), w(0), w(0)],
        [m(1), m(1), m(9), p(1), p(2), s(3), s(4), s(5), s(9), w(1), w(2), d(0), d(2)],
        [m(8), m(8), p(6), p(9), s(1), s(2), s(6), s(7), s(8), w(3), w(3), d(1), d(1)],
        [m(3), m(5), m(7), p(2), p(4), p(6), s(2), s(4), s(6), w(1), w(2), d(0), d(2)],
    ]
    drawn = s(1)  # ツモ切りすれば聴牌が保てる牌 = 立直を宣言できる
    # 河。自分の河に待ち牌（6筒・9筒）を置くとフリテン表示になるので入れない。
    discards = [
        [w(3), d(2), s(1), s(9), m(1), d(0)],
        [w(0), d(1), m(9), p(1), s(5), m(2), p(9)],
        [d(0), w(2), m(1), s(8), p(1), m(6), s(7)],
        [w(0), d(1), p(9), m(4), s(3), p(8), m(5)],
    ]
    dora_indicator = p(5)  # ドラは6筒（待ちの片方がドラになる）

    used = {}
    for tile in (
        [t for hand in hands for t in hand]
        + [t for pile in discards for t in pile]
        + [drawn, dora_indicator]
    ):
        used[tile] = used.get(tile, 0) + 1
    assert all(count <= 4 for count in used.values()), "同じ牌が5枚以上ある"

    # 見えていない牌（山の未来ぶんと王牌の残り）。
    rest = [tile for tile in _M_ORDER for _ in range(4 - used.get(tile, 0))]
    random.Random(20260907).shuffle(rest)
    dead_wall = [dora_indicator] + rest[:13]  # 先頭が表ドラ表示牌（王牌の偶数番目）

    # 山は「配牌52枚 → 実際に自摸った順 → 未来ぶん」で並べる（wallIndex より手前は二度と読まれない）。
    # 親は CPU1 なので手番は 1→2→3→0 の順。27自摸ぶん進み、28手目が自分のツモ。
    order, cursor, drawn_sequence = [1, 2, 3, 0], [0, 0, 0, 0], []
    for step in range(27):
        player = order[step % 4]
        drawn_sequence.append(discards[player][cursor[player]])
        cursor[player] += 1
    drawn_sequence.append(drawn)
    wall = [t for hand in hands for t in hand] + drawn_sequence + rest[13:]

    assert len(wall) == 122 and len(dead_wall) == 14, "山122 + 王牌14 = 136枚にならない"
    return {
        "wall": [_tile(t) for t in wall],
        "wallIndex": 80,  # 配牌52 + 自摸28。残り = 122 - 80 = 42枚
        "deadWall": [_tile(t) for t in dead_wall],
        "hands": [_hand(hand) for hand in hands],
        "drawnTile": _tile(drawn),
        "discards": [[_tile(t) for t in pile] for pile in discards],
        "riichi": [False] * 4,
        "riichiFuriten": [False] * 4,
        "scores": [30700, 22300, 25000, 22000],  # 合計 100000
        "dealer": 1,
        "roundNumber": 2,
        "honba": 0,
        "riichiSticks": 0,
        "currentPlayer": 0,  # 人間の手番で止める（最重要）
        "turnCount": 28,
        "melds": [[], [], [], []],
        "discardedKinds": [sorted({_M_INDEX[t] for t in pile}) for pile in discards],
        "revealedDoraCount": 1,
        "deadWallDraws": 0,
        "hasRevivedThisGame": False,
        "handResult": None,  # 非 null にするとリザルト画面になる
        "endsAfterThisHand": False,
    }


def _turtle_positions():
    """MahjongSolitaireLayout.turtle と同じ順序で144個の位置（layer, hx, hy）を作る。

    faces の添字はこの並び順そのものなので、順番を変えると盤の絵が変わる。
    """
    positions = []
    # 第1段の甲羅（上の行から）。座標は半マス単位で、牌1枚が 2×2 半マスを占める。
    for hy, x_from, x_to in [(0, 1, 12), (2, 3, 10), (4, 2, 11), (6, 1, 12),
                             (8, 1, 12), (10, 2, 11), (12, 3, 10), (14, 1, 12)]:
        for x in range(x_from, x_to + 1):
            positions.append((0, x * 2, hy))
    positions += [(0, 0, 7), (0, 26, 7), (0, 28, 7)]  # 左のヒレ1枚・右のヒレ2枚
    seen = set()
    for layer, xs, ys in [(1, range(4, 10), range(1, 7)),
                          (2, range(5, 9), range(2, 6)),
                          (3, range(6, 8), range(3, 5))]:
        for y in ys:
            for x in xs:
                position = (layer, x * 2, y * 2)
                if position not in seen:
                    seen.add(position)
                    positions.append(position)
    positions.append((4, 13, 7))  # 第5段の1枚
    return positions


def _turtle_relations(positions):
    """MahjongSolitaireLayout.makeRelations と同じ（上に載る牌・左右を塞ぐ牌）。"""
    n = len(positions)
    above, left, right = [[] for _ in range(n)], [[] for _ in range(n)], [[] for _ in range(n)]
    for i, (a_layer, ax, ay) in enumerate(positions):
        for j, (b_layer, bx, by) in enumerate(positions):
            if i == j:
                continue
            if b_layer > a_layer and abs(ax - bx) < 2 and abs(ay - by) < 2:
                above[i].append(j)
            elif b_layer == a_layer and abs(ay - by) < 2:
                if ax - 4 < bx < ax:
                    left[i].append(j)
                if ax < bx < ax + 4:
                    right[i].append(j)
    return above, left, right


def _free_indices(remaining, relations):
    """MahjongSolitaireRules.isFree: 上に何も載っておらず、左右どちらかが空いていれば取れる。"""
    above, left, right = relations
    result = []
    for i, alive in enumerate(remaining):
        if not alive or any(remaining[k] for k in above[i]):
            continue
        if any(remaining[k] for k in left[i]) and any(remaining[k] for k in right[i]):
            continue
        result.append(i)
    return result


def _solitaire_face_pairs():
    """MahjongSolitaireRules.facePairs: 144枚を「同時に取れる2枚」72組に分ける。"""
    pairs = []

    def two(face):
        pairs.append([face, face])
        pairs.append([face, face])

    for n in range(1, 10):
        for kind in ("characters", "circles", "bamboos"):
            two((kind, n))
    for n in range(4):
        two(("wind", n))
    for n in range(3):
        two(("dragon", n))
    # 花牌・季節牌は絵柄が違っても組にできる（matchKey が同じ）
    pairs += [[("flower", 0), ("flower", 1)], [("flower", 2), ("flower", 3)],
              [("season", 0), ("season", 1)], [("season", 2), ("season", 3)]]
    return pairs


def snapshot_mahjong():
    """麻雀ソリティア。亀甲を30組（60枚）取り進めた盤面。

    盤面は Swift 側（MahjongSolitaireRules.generate）と同じ逆順生成で作る:
    満杯の盤から「そのとき取れる2枚」を剥がし続け、その順に絵柄を割り当てるので、
    途中で止めた局面も必ず取り切れる = 実プレイで到達しうる状態になる。
    取れる組が0になると手詰まりオーバーレイが盤に被るので、最後に必ず検査する。
    """
    positions = _turtle_positions()
    assert len(positions) == len(set(positions)) == 144, "亀甲は144枚"
    relations = _turtle_relations(positions)
    rng = random.Random(20260907)

    order = None
    for _ in range(64):
        remaining, steps, left_count, ok = [True] * 144, [], 144, True
        while left_count:
            free = _free_indices(remaining, relations)
            if len(free) < 2:
                ok = False
                break
            rng.shuffle(free)
            a, b = free[0], free[1]
            remaining[a] = remaining[b] = False
            left_count -= 2
            steps.append((a, b))
        if ok:
            order = steps
            break
    assert order is not None, "取り切れる順序が見つからなかった"

    pairs = _solitaire_face_pairs()
    rng.shuffle(pairs)
    faces = [None] * 144
    for step, (a, b) in enumerate(order):
        faces[a], faces[b] = pairs[step][0], pairs[step][1]
    for a, b in order[:30]:  # 30組取った状態まで進める
        faces[a] = faces[b] = None

    remaining = [face is not None for face in faces]
    free = _free_indices(remaining, relations)

    def match_key(face):
        return face[0] if face[0] in ("flower", "season") else f"{face[0]}{face[1]}"

    available = sum(1 for i, a in enumerate(free) for b in free[i + 1:]
                    if match_key(faces[a]) == match_key(faces[b]))
    assert sum(remaining) == 84, "残り84枚（42組）"
    assert available > 0, "手詰まり = 盤にオーバーレイが被る"
    return {
        "faces": [None if f is None else {f[0]: {"_0": f[1]}} for f in faces],
        "elapsedSeconds": 267,
        "shuffleCount": 0,
        "hintCount": 1,
        "undoCount": 0,
        "layoutID": "turtle",  # 起動引数 -mahjongLayout を使うときは必ず一致させる
    }


def _daifugo_card(suit, rank):
    """DaifugoCard.makeDeck と同じ採番（id = suit*13 + rank - 1）。"""
    return {"id": suit * 13 + rank - 1, "suit": suit, "rank": rank}


def _daifugo_sort_key(card):
    """DaifugoCard.sortKey（革命を考えない素の強さ → スート）。3 が最弱・JOKER が最強。"""
    rank = card["rank"]
    base = 20 if rank == 0 else 11 if rank == 1 else 12 if rank == 2 else rank - 3
    return base * 10 + (card["suit"] or 0)


def snapshot_daifugo():
    """2ゲーム目・CPU2 が出した9のペアに対して自分の番が回ってきたところ。

    CPU の手番のまま撮ると `.task` の `runCPUTurnsIfNeeded()` が打ち続けるため、
    `currentPlayer` は必ず人間（0）にする。自分の手札を空にすると操作エリアが
    「結果まで進める」に変わってしまうので1枚以上残す。手札はモデル側でソートし直されない
    （復元は代入するだけ）ので、sortKey 順で書いておく。
    """
    deck = [_daifugo_card(s, r) for s in range(4) for r in range(1, 14)] \
        + [{"id": 52, "suit": None, "rank": 0}, {"id": 53, "suit": None, "rank": 0}]
    by_id = {card["id"]: card for card in deck}

    # 自分の手札9枚: ♠4 ♣5 ♥7 ♦7 ♠10 ♥J ♦J ♣K JOKER
    # → 場（9のペア）に対して J のペア・10/K + JOKER が出せる = ヒントの強調と減光が両方出る。
    player = [by_id[i] for i in (3, 43, 19, 32, 9, 23, 36, 51, 52)]
    field = [by_id[8], by_id[21]]  # ♠9・♥9（CPU2 が出したペア）

    used = {card["id"] for card in player + field}
    rest = [card for card in deck if card["id"] not in used]
    random.Random(20260907).shuffle(rest)
    # 残りから CPU に配る。余った14枚は「すでに出されて流れた札」（大富豪に捨て札置き場は無い）。
    hands = [player, rest[:10], rest[10:18], rest[18:29]]
    hands = [sorted(hand, key=_daifugo_sort_key) for hand in hands]

    ids = [card["id"] for hand in hands for card in hand] + [card["id"] for card in field]
    assert len(ids) == len(set(ids)), "同じカードが2箇所にある"
    return {
        "hands": hands,
        "field": field,
        "fieldOwner": 2,
        "currentPlayer": 0,  # 人間の手番で止める（最重要）
        # 自分が 7 7 → CPU1 パス → CPU2 が 9 9 → CPU3 パス、で自分に戻った状態
        "passedPlayers": [1, 3],
        "isRevolution": False,
        "finishOrder": [],
        "fouls": [],
        "gameNumber": 2,
        "lastRanking": [1, 0, 2, 3],
        "lastActions": ["7 7", "パス", "9 9", "パス"],  # 4要素でないと丸ごと無視される
    }


def snapshot_go():
    """9路盤の中盤（16手）。黒 = 人間の手番で止めるので CPU は動かない。

    盤面は保存されず `moves` の再生だけで復元される（GoModel.replay）。replay は
    非合法手の戻り値を捨てるため、混ざるとその手だけ盤に乗らず手番のパリティが狂う。
    手順は GoModel.applyPreviewMidgameForTesting()（撮影用の DEBUG コード）の preset と
    同じもので、全16手が合法・取りゼロ。
    """
    preset = [
        (2, 2), (6, 6), (2, 6), (6, 2), (4, 4),
        (3, 5), (5, 3), (4, 6), (4, 2), (5, 5),
        (3, 3), (6, 4), (2, 4), (5, 6), (3, 6),
        (5, 2),
    ]
    assert len(preset) == len(set(preset)), "同じ交点に2回打っている"
    assert len(preset) % 2 == 0, "白番で止まると CPU が着手してしまう"
    return {
        "size": 9,
        "handicap": 0,
        "komi": 6.5,
        "humanSide": 0,  # GoStone.black
        "aiLevel": 1,    # GoLevel.normal
        "startedAt": STARTED_AT,
        # GoMove は連想値つき Codable enum（play は {"play":{"_0":{...}}}）
        "moves": [{"play": {"_0": {"row": r, "col": c}}} for r, c in preset],
        "undoUsed": False,
        "phase": 0,  # GoPhase.playing（1 = scoring だと死活計算が走る）
    }


def snapshot_chess():
    """イタリアンゲームを12手進めた序盤〜中盤。白（人間）の手番。

    将棋と同じく盤は保存せず「開始 FEN + UCI の手順」だけを持つので、キャスリング権や
    アンパッサン標的は再生で自動的に揃う。黒番のまま撮ると ChessView の
    `.task(id: model.aiTurnKey)` が発火して撮影中に CPU が指してしまう。
    """
    moves = [
        "e2e4", "e7e5",
        "g1f3", "b8c6",
        "f1c4", "f8c5",
        "c2c3", "g8f6",
        "d2d3", "d7d6",
        "e1g1", "e8g8",  # UCI ではキャスリングもキングの移動として書く
    ]
    assert len(moves) % 2 == 0, "黒番で止めると CPU が指してしまう"
    return {
        "initialFen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        "moves": moves,
        "phase": "playing",
        "reviewPly": None,
        "white": "human",
        "black": "ai",
        "aiLevel": 1,
        "startedAt": STARTED_AT,
        "undoUsed": False,
        "resigned": False,
    }


def snapshot_solitaire():
    """配札の種だけを固定するスナップショット（moves は空）。

    ソリティアには設定シートが無いので、このファイルの役目はシート回避ではなく
    **配札の決定化**。置かないと SolitaireModel.pickSeed() が毎回別の配札を引く。

    盤面は保存されない設計（種 + 手順から再生）で、手順を JSON で書くには Swift の
    `Array.shuffle(using:)` を Python へ移植して配札を再現する必要がある。移植の正しさを
    確かめる手立てが無いので、中盤の絵は撮影用の DEBUG 経路 `-solitaireMidgame`
    （= ソルバーの勝ち筋の45%まで進める）に任せる。この経路は moves が空のときだけ
    発火するため、ここは必ず空にしておくこと。
    """
    return {
        # SolitaireVerifiedSeeds に載っている = ソルバー検証済みでクリア可能な種だけ使う
        "seed": 3,
        "moves": [],
        "elapsedSeconds": 143,  # 02:23。マインスイーパーと同じく撮影中も1秒ずつ進む
        "jokerGrants": 1,       # SolitaireModel.initialJokerGrants
        "undosRemaining": 3,    # SolitaireUndoBudget.free
    }


def snapshot_blocks():
    """ステージ6（ダイヤ型）の開始時点。スコア 4560・残機2。

    ブロック崩しはフレーム単位では保存しない設計で、スナップショットは
    「ステージ・累計スコア・残機・コンティニュー使用済みか」だけを持つ。復元後の
    phase は必ず `.ready`（発射待ち）になり、`BlocksModel.tick` が
    `guard phase == .playing` で弾くので**球は完全に静止する**。SKAction も常時
    アニメも無いのでそのまま撮ってよい（`-simulateBlocks playing` は球が動く）。

    スコアは「1〜5面をクリアし5面で1機落とした」ときの BlocksScoring の計算と一致させた:
      ブロック点 = (normal*10 + hard*35) * (1 + (stage-1)//3) / クリア点 = 100*stage + 50*残機
      520 + 580 + 700 + 1640 + 1120 = 4560
    """
    return {
        "stage": 6,  # 1...12（BlocksRules.stageCount）
        "score": 4560,
        "lives": 2,  # 初期3（BlocksRules.initialLives）。0 は .ready と矛盾する
        "continueUsed": False,
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
    # v1.1.3 で16本になったぶん（#184）。麻雀ソリティアの gameID が "mahjong"、
    # 四人打ちが "mahjong4" という紛らわしい対応なので取り違えないこと。
    "sudoku": snapshot_sudoku,
    "mahjong4": snapshot_mahjong4,
    "mahjong": snapshot_mahjong,
    "daifugo": snapshot_daifugo,
    "go": snapshot_go,
    "chess": snapshot_chess,
    "solitaire": snapshot_solitaire,
    "blocks": snapshot_blocks,
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
