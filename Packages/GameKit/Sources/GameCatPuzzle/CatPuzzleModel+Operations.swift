import Foundation
import Core
import CoreEngine

/// `CatPuzzleModel` の盤の操作（スライドで続けて ×・猫を見つける・戻す・ヒント・新規ゲーム）。挙動は本体と同じで、ファイルだけ分けている（#3309）。

extension CatPuzzleModel {
    // MARK: - スライドで続けて ×（#3116）

    /// 指の動きがマスの一辺のこの割合に届くまではタップとして扱う（届いたらスライド）。
    public static let slideThreshold: Double = 0.4

    /// スライドと決める指の動き（pt）。マスの一辺の `slideThreshold` 倍だが、12×12 のような小さいマス
    /// （iPhone SE で約 27pt）でタップのわずかな指のぶれがスライドにならないよう、9×9 の SE と同じ 14pt を下限にする（#3201）。
    public static func slideDistance(cellSide: CGFloat) -> CGFloat {
        max(cellSide * slideThreshold, 14)
    }

    /// 盤の座標（盤の左上が原点）から、いま指があるマスの番号。盤の外（余白・枠の外）は nil。
    public static func cell(at point: CGPoint, side: Int, cellSide: CGFloat, inset: CGFloat) -> Int? {
        let col = Int(((point.x - inset) / cellSide).rounded(.down))
        let row = Int(((point.y - inset) / cellSide).rounded(.down))
        guard (0..<side).contains(col), (0..<side).contains(row) else { return nil }
        return row * side + col
    }

    /// `from` から `to` までに通ったマス（両端を含む。マスの中心どうしを結ぶ線）。速いスライドで飛んだマスを埋める。
    public static func cellsOnLine(from: Int, to: Int, side: Int) -> [Int] {
        var (col, row) = (from % side, from / side)
        let (endCol, endRow) = (to % side, to / side)
        let dx = abs(endCol - col), dy = abs(endRow - row)
        let (stepX, stepY) = (col < endCol ? 1 : -1, row < endRow ? 1 : -1)
        var error = dx - dy
        var cells = [row * side + col]
        while col != endCol || row != endRow {
            let doubled = error * 2
            if doubled > -dy { error -= dy; col += stepX }
            if doubled < dx { error += dx; row += stepY }
            cells.append(row * side + col)
        }
        return cells
    }

    /// スライドの開始（指が `slideThreshold` 以上動いて、スライドと決まったとき）。最初のマスの印で向きを決め、
    /// そのマスにも適用する。ダブルタップの控え（`pendingTap`）は捨てる。
    public func beginCrossDrag(cell: Int) {
        pendingTap = nil
        guard !isFrozen, marks.indices.contains(cell) else { return }
        // 鍵の部屋の外から始めたスライドは受け付けない（案内は 1 回だけ）。
        if isLockedOut(cell: cell) {
            rejectLockedTouch()
            return
        }
        crossDrag = CrossDrag(adds: marks[cell] != .cross)
        dragCross(to: cell)
    }

    /// 指が `cell` に来た（盤の外に出ているときは nil）。前のマスとの間も通ったものとして、向きに合うマスだけ変える。
    /// 同じマスは 1 回のスライドで 1 回しか変えない。猫・決まった印のマスは変えない。
    public func dragCross(to cell: Int?) {
        guard var drag = crossDrag, !isFrozen else { return }
        defer { crossDrag = drag }
        guard let cell, marks.indices.contains(cell) else {
            drag.last = nil
            return
        }
        let path = drag.last.map { Self.cellsOnLine(from: $0, to: cell, side: puzzle.side) } ?? [cell]
        drag.last = cell
        for passed in path where !drag.changed.contains(passed) {
            guard !isFixed(cell: passed), marks[passed] != .cat, !isLockedOut(cell: passed),
                  marks[passed] == (drag.adds ? .empty : .cross) else { continue }
            if !drag.hasChangedAny {
                // 最初に変わるときに 1 回だけ履歴を積む（スライド全体が「戻す」1 回ぶん・手数も 1）。
                drag.hasChangedAny = true
                startPlayIfPending()
                lastHint = nil
                lastWrongCell = nil
                moves += 1
                if !stopwatch.isRunning { startTimer() }
                services?.gameDidProgress(gameID: Self.gameID)
                history.append(marks)
            }
            drag.changed.insert(passed)
            marks[passed] = drag.adds ? .cross : .empty
            services?.feedback.impact(.light)
        }
    }

    /// 指を離した（スライドの確定）。変わったマスがあれば保存する。
    public func endCrossDrag() {
        guard let drag = crossDrag else { return }
        crossDrag = nil
        if drag.hasChangedAny { persist() }
    }

    /// ダブルタップ: そのマスで猫を見つける（空でも × でも同じ）。答えのマスなら猫を置き、答えでなければ猫は置かず
    /// 赤い × を固定で置いてミスを 1 数える。猫のいるマス・ヒントで置いた猫・×、赤い × のマスでは何もしない。
    public func findCat(cell: Int) {
        pendingTap = nil
        guard !isFrozen, marks.indices.contains(cell), !isFixed(cell: cell), marks[cell] != .cat else { return }
        if isLockedOut(cell: cell) {
            rejectLockedTouch()
            return
        }
        let wasLocked = isKeyLocked
        startPlayIfPending()
        lastHint = nil
        lastWrongCell = nil
        moves += 1
        if !stopwatch.isRunning { startTimer() }
        services?.gameDidProgress(gameID: Self.gameID)
        if !puzzle.solutionCells.contains(cell) {
            // 戻せない印なので履歴には積まない（「戻す」で取り消せる操作ではない）。
            marks[cell] = .cross
            wrongCrosses.insert(cell)
            lastWrongCell = cell
            mistakes += 1
            // 置いた猫の数 ÷ 盤の辺（%）を「どこまで進めてミスしたか」として載せる（#3232）。
            services?.gameDidMiss(
                gameID: Self.gameID, cause: nil, progressPercent: catCells.count * 100 / puzzle.side
            )
            if mistakes >= Self.maxMistakes {
                if continueUsed {
                    fail()
                } else {
                    offerContinue()
                }
            } else {
                services?.feedback.impact(.cat(.miss))
                persist()
            }
            return
        }
        history.append(marks)
        marks[cell] = .cat
        noteKeyOpened(wasLocked: wasLocked)
        playFoundSound(wasLocked: wasLocked)
        if CatPuzzleLogic.isSolved(puzzle: puzzle, cats: catCells) {
            finish()
        } else {
            persist()
        }
    }

    /// 直前の × の付け外し・見つけた猫を取り消す。ヒントで置いた猫・×、赤い × は戻しても残る。
    public func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        pendingTap = nil
        crossDrag = nil  // 進行中のスライドは捨てる（盤が変わるため）
        marks = previous
        keepFixedMarks()
        lastHint = nil
        lastWrongCell = nil
        moves += 1
        services?.feedback.impact(.light)
        persist()
    }

    /// 印を全部消して同じ問題を最初から。ミス・ヒント・経過秒は引き継ぎ、ヒントで置いた猫・×、赤い × も残る。
    public func reset() {
        guard !isFrozen else { return }
        history.removeAll()
        pendingTap = nil
        crossDrag = nil  // 進行中のスライドは捨てる（盤が変わるため）
        marks = Array(repeating: .empty, count: puzzle.cellCount)
        keepFixedMarks()
        lastHint = nil
        lastWrongCell = nil
        services?.feedback.impact(.light)
        // 印の無い盤は保存しない（開いただけの盤を「続き」にしない）。ヒント・赤い × の印があれば保存する。
        persist()
    }

    /// ヒントを 1 回使う。推理の 1 歩（`CatPuzzleLogic.hint`）を盤に反映する: 確定した × を置き、猫が確定する
    /// ときだけ猫を置く。答えでない位置の猫があれば先にそれを × に変える。ヒントで置いた猫・× は印付きで消せない。
    /// 回数は必ず 1 だけ減り、盤は必ず 1 歩進む。置いた結果で盤が完成すればそのままクリア。
    /// 無料ぶんだけを使う。使い切っていたら何もしない（広告の 1 回は `grantAdHint(forGame:)`）。
    public func useHint() {
        guard canHint, !needsAdForHint, let hint = nextHint else { return }
        if stage != nil {
            stageHintsLeft -= 1
            stageDefaults.set(stageHintsLeft, forKey: Self.stageHintsLeftKey)
        } else if !hints.consume() {
            return
        }
        apply(hint)
    }

    /// 広告を最後まで見たあとの 1 回。`game` は広告を出す前に控えた `gameSerial`。
    /// 局が入れ替わっていた・終局した・無料ぶんが残っている・盤を進める手が無いときは適用せず false（回数も減らさない）。
    @discardableResult
    public func grantAdHint(forGame game: Int) -> Bool {
        guard game == gameSerial, canHint, needsAdForHint, let hint = nextHint else { return false }
        // ステージは広告 1 回で 1 回ぶん（残りは 0 のまま）。自由に遊ぶは広告枠を 1 つ使う。
        if stage == nil, !hints.consumeAd() { return false }
        apply(hint)
        return true
    }
    /// 「餌をあげる」の皿を消す。
    public func clearLure() { lureCell = nil }

    /// 猫を 1 匹教える（ステージだけ。画面の名前は「餌をあげる」）。無料ぶんを使う。使い切っていたら何もしない（広告の 1 回は `grantAdTeach(forGame:)`）。
    public func teachCat() {
        guard canTeach, !needsAdForTeach, let cell = nextUnplacedCat else { return }
        stageTeachLeft -= 1
        stageDefaults.set(stageTeachLeft, forKey: Self.stageTeachLeftKey)
        placeTaughtCat(at: cell)
    }

    /// 広告を最後まで見たあとの「猫を 1 匹教える」1 回。局が入れ替わっていた・終局した・無料ぶんが残っているときは適用せず false。
    @discardableResult
    public func grantAdTeach(forGame game: Int) -> Bool {
        guard game == gameSerial, canTeach, needsAdForTeach, let cell = nextUnplacedCat else { return false }
        placeTaughtCat(at: cell)
        return true
    }

    /// 教えた猫を正解のマスに置く。ヒントで置いた猫と同じ扱い（印付き・固定）。置いた結果で盤が完成すればそのままクリア。
    private func placeTaughtCat(at cell: Int) {
        pendingTap = nil
        crossDrag = nil  // 進行中のスライドは捨てる（盤が変わるため）
        startPlayIfPending()
        let wasLocked = isKeyLocked
        lureCell = cell
        lureToken += 1
        marks[cell] = .cat
        hintCells.insert(cell)
        noteKeyOpened(wasLocked: wasLocked)
        stageAssistsUsed += 1
        lastHint = nil
        lastWrongCell = nil
        moves += 1
        if !stopwatch.isRunning { startTimer() }
        services?.gameDidUseTeach(gameID: Self.gameID)
        services?.gameDidProgress(gameID: Self.gameID)
        playFoundSound(wasLocked: wasLocked)
        if CatPuzzleLogic.isSolved(puzzle: puzzle, cats: catCells) {
            finish()
        } else {
            persist()
        }
    }

    /// ステージ共通のヒント・猫を教えるの残りに足して保存する（前日のランキングの特典・#3256）。
    func addStageSupply(hints: Int, teaches: Int) {
        stageHintsLeft = min(stageHintsLeft + max(0, hints), Self.stageSupplyCap)
        stageTeachLeft = min(stageTeachLeft + max(0, teaches), Self.stageSupplyCap)
        stageDefaults.set(stageHintsLeft, forKey: Self.stageHintsLeftKey)
        stageDefaults.set(stageTeachLeft, forKey: Self.stageTeachLeftKey)
    }

    /// 保存してある残り。鍵が無ければ（初回・既存の利用者）全回数、壊れた値は範囲に丸める。
    static func storedSupply(_ defaults: UserDefaults, _ key: String) -> Int {
        guard defaults.object(forKey: key) != nil else { return stageSupplyCount }
        return min(max(defaults.integer(forKey: key), 0), stageSupplyCap)
    }

    /// ヒントの中身を盤に反映する（回数の消費は呼び出し側が済ませている）。
    private func apply(_ hint: CatPuzzleHint) {
        pendingTap = nil
        crossDrag = nil  // 進行中のスライドは捨てる（盤が変わるため）
        startPlayIfPending()
        let wasLocked = isKeyLocked
        for cell in hint.removed + hint.crossed {
            marks[cell] = .cross
            hintCrosses.insert(cell)
        }
        if let placed = hint.placed {
            marks[placed] = .cat
            hintCells.insert(placed)
        }
        noteKeyOpened(wasLocked: wasLocked)
        lastHint = hint
        lastWrongCell = nil
        if stage != nil { stageAssistsUsed += 1 }
        moves += 1
        if !stopwatch.isRunning { startTimer() }
        services?.gameDidUseHint(gameID: Self.gameID)
        services?.gameDidProgress(gameID: Self.gameID)
        playFoundSound(wasLocked: wasLocked)
        if CatPuzzleLogic.isSolved(puzzle: puzzle, cats: catCells) {
            finish()
        } else {
            persist()
        }
    }

    /// ヒントで置いた猫・×、赤い × を盤に戻す（「戻す」「やり直し」で消えないように）。
    private func keepFixedMarks() {
        for cell in hintCells where marks.indices.contains(cell) { marks[cell] = .cat }
        for cell in hintCrosses.union(wrongCrosses) where marks.indices.contains(cell) { marks[cell] = .cross }
    }

    /// 新規ゲーム（自由に遊ぶ）。`size` を渡すと盤の大きさを変える。ステージの途中からでも自由に遊ぶへ切り替わる。
    public func newGame(size newSize: CatPuzzleSize? = nil) {
        size = (newSize ?? size).freePlaySize
        cancelStagePreparation()
        begin(puzzle: Self.makePuzzle(size: size, generator: &generator), size: size, stage: nil)
    }
}
