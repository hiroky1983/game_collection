import Testing
@testable import GameDaifugo
@testable import GameGomoku
@testable import GameMahjongSolitaire
@testable import GameMinesweeper
@testable import GameOthello
@testable import GameShogi
@testable import GameSudoku
@testable import GameGo
@testable import MahjongTiles

/// VoiceOver の読み上げ文（#188）。
///
/// 「読み上げられるか」自体はシミュレータ上の VoiceOver でしか確かめられないが、
/// **何が読み上げられるか**（駒種・位置・取れる/取れない・選択中）は純関数なので
/// ここで固定する。盤面の状態を増やしたときに読み上げ文の更新を忘れると落ちる。
@Suite("将棋の読み上げ文")
struct ShogiAccessibilityTests {

    @Test("マスは筋段と駒種を読む") func square() {
        // index 60 = file 6(=7筋) / rank 6(=七段)
        let label = ShogiAccessibility.squareLabel(
            index: 60,
            piece: Piece(type: .pawn, color: .black),
            isSelected: false, isTarget: false, isLastMove: false
        )
        #expect(label == "7七、先手の歩")
    }

    @Test("成り駒は盤面の1文字ではなく語で読む") func promoted() {
        let label = ShogiAccessibility.squareLabel(
            index: 0,
            piece: Piece(type: .knight, color: .white, promoted: true),
            isSelected: false, isTarget: false, isLastMove: false
        )
        // 盤面表記は「圭」だが、読み上げても意味が伝わらないので「成桂」を使う
        // （index 0 は file 0 = USI ファイル 1 なので 1筋一段）
        #expect(label == "1一、後手の成桂")
        #expect(!label.contains("圭"))
    }

    @Test("空きマスと状態が読み上げに出る") func states() {
        let empty = ShogiAccessibility.squareLabel(
            index: 40, piece: nil,
            isSelected: false, isTarget: true, isLastMove: false
        )
        #expect(empty == "5五、空きマス、ここに指せます")

        let capture = ShogiAccessibility.squareLabel(
            index: 40, piece: Piece(type: .rook, color: .white),
            isSelected: false, isTarget: true, isLastMove: true
        )
        #expect(capture == "5五、後手の飛車、取れます、直前の手")

        let selected = ShogiAccessibility.squareLabel(
            index: 40, piece: Piece(type: .king, color: .black),
            isSelected: true, isTarget: false, isLastMove: false
        )
        #expect(selected == "5五、先手の玉、選択中")
    }

    @Test("持ち駒は枚数と選択状態を読む") func hand() {
        #expect(ShogiAccessibility.handLabel(type: .silver, color: .black, count: 2, isSelected: false)
                == "先手の持ち駒、銀2枚")
        #expect(ShogiAccessibility.handLabel(type: .pawn, color: .white, count: 1, isSelected: true)
                == "後手の持ち駒、歩1枚、選択中")
    }

    @Test("全駒種・成り駒に読みがある") func allPieces() {
        for type in PieceType.allCases {
            for promoted in [false, true] where !(promoted && !type.canPromote) {
                let name = ShogiAccessibility.pieceName(
                    Piece(type: type, color: .black, promoted: promoted)
                )
                #expect(!name.isEmpty)
            }
        }
    }
}

@Suite("五目並べの読み上げ文")
struct GomokuAccessibilityTests {

    @Test("交点は行列と石の色を読む") func point() {
        #expect(GomokuAccessibility.pointLabel(row: 7, col: 7, stone: .black, isLastMove: false)
                == "8行8列、黒石")
        #expect(GomokuAccessibility.pointLabel(row: 0, col: 14, stone: .white, isLastMove: true)
                == "1行15列、白石、直前の手")
        #expect(GomokuAccessibility.pointLabel(row: 3, col: 2, stone: nil, isLastMove: false)
                == "4行3列、空点")
    }
}

@Suite("オセロの読み上げ文")
struct OthelloAccessibilityTests {

    @Test("マスは石の色と置けるかを読む") func square() {
        #expect(OthelloAccessibility.squareLabel(row: 3, col: 3, stone: .white,
                                                 isValidMove: false, isLastMove: false)
                == "4行4列、白")
        #expect(OthelloAccessibility.squareLabel(row: 2, col: 3, stone: nil,
                                                 isValidMove: true, isLastMove: false)
                == "3行4列、空、ここに置けます")
        #expect(OthelloAccessibility.squareLabel(row: 7, col: 7, stone: .black,
                                                 isValidMove: false, isLastMove: true)
                == "8行8列、黒、直前の手")
    }

    @Test("初期盤面の合法手が読み上げに出る") func validMovesFromBoard() {
        let board = OthelloBoard()
        let valid = Set(board.validMoves(for: .black).map { $0.0 * othelloBoardSize + $0.1 })
        let labels = valid.map { idx in
            OthelloAccessibility.squareLabel(
                row: idx / othelloBoardSize, col: idx % othelloBoardSize,
                stone: board[idx / othelloBoardSize, idx % othelloBoardSize],
                isValidMove: true, isLastMove: false
            )
        }
        #expect(labels.count == 4)
        #expect(labels.allSatisfy { $0.hasSuffix("空、ここに置けます") })
    }
}

@Suite("マインスイーパーの読み上げ文")
struct MinesweeperAccessibilityTests {

    private func cell(revealed: Bool = false, flagged: Bool = false,
                      mine: Bool = false, adjacent: Int = 0,
                      continued: Bool = false) -> MinesweeperCell {
        var c = MinesweeperCell()
        c.isRevealed = revealed
        c.isFlagged = flagged
        c.isMine = mine
        c.adjacentMines = adjacent
        c.isContinuedMine = continued
        return c
    }

    @Test("未開放・旗・数字・空きを読み分ける") func states() {
        #expect(MinesweeperAccessibility.cellLabel(row: 0, col: 0, cell: cell(),
                                                   isHit: false, gameOver: false)
                == "1行1列、未開放")
        #expect(MinesweeperAccessibility.cellLabel(row: 0, col: 0, cell: cell(continued: true),
                                                   isHit: false, gameOver: false)
                == "1行1列、確定した地雷")
        #expect(MinesweeperAccessibility.cellLabel(row: 2, col: 4, cell: cell(flagged: true),
                                                   isHit: false, gameOver: false)
                == "3行5列、旗")
        #expect(MinesweeperAccessibility.cellLabel(row: 2, col: 4, cell: cell(revealed: true, adjacent: 3),
                                                   isHit: false, gameOver: false)
                == "3行5列、周囲の地雷3")
        #expect(MinesweeperAccessibility.cellLabel(row: 2, col: 4, cell: cell(revealed: true),
                                                   isHit: false, gameOver: false)
                == "3行5列、空き")
    }

    @Test("誤った旗は終局後にだけ告げる（画面表示と同じ扱い）") func wrongFlag() {
        let flaggedSafe = cell(flagged: true)
        #expect(MinesweeperAccessibility.cellLabel(row: 0, col: 0, cell: flaggedSafe,
                                                   isHit: false, gameOver: false)
                == "1行1列、旗")
        #expect(MinesweeperAccessibility.cellLabel(row: 0, col: 0, cell: flaggedSafe,
                                                   isHit: false, gameOver: true)
                == "1行1列、誤った旗")
    }

    @Test("踏んだ地雷を区別する") func mines() {
        let mine = cell(revealed: true, mine: true)
        #expect(MinesweeperAccessibility.cellLabel(row: 1, col: 1, cell: mine,
                                                   isHit: true, gameOver: true)
                == "2行2列、踏んだ地雷")
        #expect(MinesweeperAccessibility.cellLabel(row: 1, col: 1, cell: mine,
                                                   isHit: false, gameOver: true)
                == "2行2列、地雷")
    }

    @Test("旗モードでヒントが変わる") func hint() {
        #expect(MinesweeperAccessibility.cellHint(flagMode: true, canReveal: true, canToggleFlag: true)
                == "ダブルタップで旗を切り替えます")
        #expect(MinesweeperAccessibility.cellHint(flagMode: false, canReveal: true, canToggleFlag: true)
                == "ダブルタップで開きます")
    }

    @Test("実行できない操作はヒントで案内しない") func hintSuppressedWhenUnavailable() {
        // 開き済みのマス: 開けないし旗も置けない
        #expect(MinesweeperAccessibility.cellHint(flagMode: false, canReveal: false, canToggleFlag: false)
                .isEmpty)
        #expect(MinesweeperAccessibility.cellHint(flagMode: true, canReveal: false, canToggleFlag: false)
                .isEmpty)
        // 旗の立っているマス: 開けないが旗は下ろせる
        #expect(MinesweeperAccessibility.cellHint(flagMode: false, canReveal: false, canToggleFlag: true)
                .isEmpty)
        #expect(MinesweeperAccessibility.cellHint(flagMode: true, canReveal: false, canToggleFlag: true)
                == "ダブルタップで旗を切り替えます")
    }

    @Test("操作の可否は Model が唯一の出どころ") @MainActor func modelIsSourceOfTruth() {
        let model = MinesweeperModel(services: nil, rows: 9, cols: 9, mines: 10)
        #expect(model.canReveal(row: 0, col: 0))
        #expect(model.canToggleFlag(row: 0, col: 0))

        model.toggleFlag(row: 0, col: 0)
        // 旗を立てたら開けないが、旗は下ろせる
        #expect(!model.canReveal(row: 0, col: 0))
        #expect(model.canToggleFlag(row: 0, col: 0))

        model.tap(row: 4, col: 4)
        #expect(!model.canReveal(row: 4, col: 4))     // 開き済み
        #expect(!model.canToggleFlag(row: 4, col: 4)) // 開き済みには旗を置けない
    }
}

@Suite("大富豪の読み上げ文")
struct DaifugoAccessibilityTests {

    @Test("スート記号ではなく語で読む") func cardName() {
        let heart7 = DaifugoCard(id: 19, suit: .hearts, rank: 7)
        #expect(DaifugoAccessibility.cardName(heart7) == "ハートの7")
        #expect(!DaifugoAccessibility.cardName(heart7).contains("♥"))
    }

    @Test("絵札とジョーカーの読み") func faceCards() {
        #expect(DaifugoAccessibility.cardName(DaifugoCard(id: 0, suit: .spades, rank: 1))
                == "スペードのエース")
        #expect(DaifugoAccessibility.cardName(DaifugoCard(id: 11, suit: .clubs, rank: 12))
                == "クラブのクイーン")
        #expect(DaifugoAccessibility.cardName(DaifugoCard(id: 52, suit: nil, rank: DaifugoRules.jokerRank))
                == "ジョーカー")
    }

    @Test("手札は選択状態を読む") func selection() {
        let card = DaifugoCard(id: 40, suit: .diamonds, rank: 13)
        #expect(DaifugoAccessibility.handCardLabel(card, isSelected: false) == "ダイヤのキング")
        #expect(DaifugoAccessibility.handCardLabel(card, isSelected: true) == "ダイヤのキング、選択中")
    }

    @Test("場は出ている組をまとめて読む") func field() {
        #expect(DaifugoAccessibility.fieldLabel([]) == "場は流れています")
        let pair = [DaifugoCard(id: 5, suit: .spades, rank: 6),
                    DaifugoCard(id: 18, suit: .hearts, rank: 6)]
        #expect(DaifugoAccessibility.fieldLabel(pair) == "場のカード、スペードの6、ハートの6")
    }

    @Test("場は出し手も読む（バッジは見た目にしか出ないため・#193）") func fieldOwner() {
        let pair = [DaifugoCard(id: 5, suit: .spades, rank: 6),
                    DaifugoCard(id: 18, suit: .hearts, rank: 6)]
        #expect(DaifugoAccessibility.fieldLabel(pair, ownerName: "CPU2")
                == "場のカード、スペードの6、ハートの6。CPU2が出しました")
        // 場が空なら出し手そのものが無いので、渡されても読まない。
        #expect(DaifugoAccessibility.fieldLabel([], ownerName: "CPU2") == "場は流れています")
    }

    @Test("配りうる54枚すべてに読みがある") func wholeDeck() {
        let names = DaifugoCard.makeDeck().map(DaifugoAccessibility.cardName)
        #expect(names.count == 54)
        #expect(names.allSatisfy { !$0.isEmpty })
    }
}

@Suite("麻雀ソリティアの読み上げ文")
struct MahjongAccessibilityTests {

    @Test("牌の呼び名は種類と数に開く") func tileNames() {
        #expect(MahjongFace.characters(1).displayName == "萬子の1")
        #expect(MahjongFace.circles(5).displayName == "筒子の5")
        #expect(MahjongFace.bamboos(9).displayName == "索子の9")
        #expect(MahjongFace.wind(0).displayName == "字牌の東")
        #expect(MahjongFace.dragon(2).displayName == "字牌の白")
        #expect(MahjongFace.flower(3).displayName == "花牌の竹")
        #expect(MahjongFace.season(1).displayName == "季節牌の夏")
    }

    @Test("標準34種すべてに固有の読みがある") func allStandardTilesAreDistinct() {
        let names = MahjongTile.all.map(\.displayName)
        #expect(names.count == 34)
        #expect(Set(names).count == 34)
    }

    @Test("取れるか・選択中・ヒントが読み上げに出る") func tileLabel() {
        #expect(MahjongSolitaireAccessibility.tileLabel(
            face: .circles(3), isBlocked: false, isSelected: false, isHinted: false
        ) == "筒子の3、取れます")

        #expect(MahjongSolitaireAccessibility.tileLabel(
            face: .circles(3), isBlocked: true, isSelected: false, isHinted: false
        ) == "筒子の3、取れません")

        #expect(MahjongSolitaireAccessibility.tileLabel(
            face: .wind(1), isBlocked: false, isSelected: true, isHinted: true
        ) == "字牌の南、取れます、選択中、ヒント")
    }

    @Test("値域外の牌でも読み上げ文の生成で落ちない") func invalidFaceIsSafe() {
        // スナップショット破損などで値域外が来ても、読み上げ側は落とさない
        #expect(!MahjongFace.wind(9).displayName.isEmpty)
        #expect(!MahjongFace.flower(-1).displayName.isEmpty)
    }
}

@Suite("囲碁の読み上げ文")
struct GoAccessibilityTests {

    @Test("交点は 行・列・石の色 の順で読む")
    func pointLabel() {
        #expect(GoAccessibility.pointLabel(row: 0, col: 0, stone: nil, isLastMove: false)
                == "1行1列、空点")
        #expect(GoAccessibility.pointLabel(row: 4, col: 4, stone: .black, isLastMove: false)
                == "5行5列、黒石")
        #expect(GoAccessibility.pointLabel(row: 8, col: 2, stone: .white, isLastMove: true)
                == "9行3列、白石、直前の手")
    }

    /// 死に石は画面では × 印で分かる。読み上げに入れないと、その情報が音声の利用者にだけ届かない。
    @Test("終局の死に石は読み上げに含める")
    func deadStoneIsAnnounced() {
        #expect(GoAccessibility.pointLabel(row: 1, col: 1, stone: .white, isLastMove: false, isDead: true)
                == "2行2列、白石、死に石")
        #expect(GoAccessibility.pointLabel(row: 1, col: 1, stone: .white, isLastMove: true, isDead: true)
                == "2行2列、白石、死に石、直前の手")
    }

    @Test("ステータスは局面ごとに要点だけを読む")
    func statusLabel() {
        #expect(GoAccessibility.statusLabel(
            phase: .playing, isHumanTurn: true, capturedByHuman: 2, capturedByCPU: 1, result: nil
        ) == "あなたの番、あなたが取った石 2、CPUが取った石 1")
        #expect(GoAccessibility.statusLabel(
            phase: .scoring, isHumanTurn: false, capturedByHuman: 0, capturedByCPU: 0, result: nil
        ) == "終局の確認。計算中")
        #expect(GoAccessibility.statusLabel(
            phase: .finished, isHumanTurn: false, capturedByHuman: 0, capturedByCPU: 0,
            result: "白 6.5目勝ち"
        ) == "白 6.5目勝ち")
    }
}

@Suite("数独の読み上げ文")
struct SudokuAccessibilityTests {

    @Test("入っている数字と出処を読む") func filledCell() {
        #expect(SudokuAccessibility.cellLabel(
            row: 2, col: 4, digit: 7, isGiven: true, isHinted: false,
            isError: false, noteDigits: [], isSelected: false
        ) == "3行5列、7、出題")

        #expect(SudokuAccessibility.cellLabel(
            row: 0, col: 0, digit: 3, isGiven: false, isHinted: true,
            isError: false, noteDigits: [], isSelected: true
        ) == "1行1列、3、ヒント、選択中")

        #expect(SudokuAccessibility.cellLabel(
            row: 8, col: 8, digit: 9, isGiven: false, isHinted: false,
            isError: true, noteDigits: [], isSelected: false
        ) == "9行9列、9、間違い")
    }

    @Test("空きマスとメモを読み分ける") func emptyCell() {
        #expect(SudokuAccessibility.cellLabel(
            row: 4, col: 4, digit: 0, isGiven: false, isHinted: false,
            isError: false, noteDigits: [], isSelected: false
        ) == "5行5列、空きマス")

        #expect(SudokuAccessibility.cellLabel(
            row: 4, col: 4, digit: 0, isGiven: false, isHinted: false,
            isError: false, noteDigits: [1, 5, 9], isSelected: false
        ) == "5行5列、メモ 1、5、9")
    }

    @Test("実行できない操作は案内しない") func hints() {
        #expect(SudokuAccessibility.cellHint(isGiven: false, isPlaying: true) == "ダブルタップで選びます")
        #expect(SudokuAccessibility.cellHint(isGiven: true, isPlaying: true) == "")
        #expect(SudokuAccessibility.cellHint(isGiven: false, isPlaying: false) == "")
    }

    @Test("数字パッドはメモモードと使い切りを読む") func padLabels() {
        #expect(SudokuAccessibility.padLabel(digit: 3, noteMode: false, isExhausted: false) == "3")
        #expect(SudokuAccessibility.padLabel(digit: 3, noteMode: true, isExhausted: false) == "メモ 3")
        #expect(SudokuAccessibility.padLabel(digit: 3, noteMode: false, isExhausted: true) == "3、使い切り")
    }

    @Test("ヒントとステータスは残量を読む") func statusLabels() {
        #expect(SudokuAccessibility.hintLabel(remaining: 2) == "ヒント、残り2回")
        #expect(SudokuAccessibility.hintLabel(remaining: 0) == "ヒント、残りなし")
        #expect(SudokuAccessibility.statusLabel(remainingCells: 30, elapsedSeconds: 75) == "残り30マス、経過1分15秒")
        #expect(SudokuAccessibility.statusLabel(remainingCells: 1, elapsedSeconds: 9) == "残り1マス、経過9秒")
    }
}
