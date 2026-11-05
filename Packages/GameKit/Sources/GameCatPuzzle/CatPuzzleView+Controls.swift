import SwiftUI
import Core
import CoreOjisanPixel

/// `CatPuzzleView` の盤の下（メッセージ行・ヒント・操作ボタン）。挙動は本体と同じで、ファイルだけ分けている（#3309）。
extension CatPuzzleView {
    // MARK: - 盤の下

    /// 盤の下の 1 行。ヒント・赤い × の説明・終局のおじさんの一言。高さは常に確保して盤が跳ねないようにする。
    var messageLine: some View {
        ZStack {
            if model.isSolved {
                // おじさんの一言は横いっぱいの吹き出しにして、文字が窮屈にならないようにする（会長 QA 2026-10-21・build 42）。
                ojisanLine(face: .cheer, text: tr(model.uncleLine ?? CatPuzzleUncleLines.clearNormal[0]))
            } else if model.isFailed {
                ojisanLine(face: .frown, text: tr(model.uncleLine ?? CatPuzzleUncleLines.fail[0]))
            } else if model.lastWrongCell != nil, model.mistakesRemaining == 1 {
                // 残りミス 1 回は一段強く（アイコン付き・太字）。次の 1 回で終わることを見逃さないようにする。
                Label(tr("あと1回で終わり！ そこに猫はいない"), systemImage: "exclamationmark.triangle.fill")
                    .scaledFont(15, weight: .heavy, design: .rounded)
                    .foregroundStyle(Theme.coralText)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            } else if model.lastWrongCell != nil {
                Text(tr("そこに猫はいない！ 赤い×でライフが減った（あと%lld回で終わり）", model.mistakesRemaining))
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.coralText)
                    .multilineTextAlignment(.center)
                    // 読み上げは `onChange` の通知で伝える。
                    .accessibilityHidden(true)
            } else if showsKeyOpened {
                Label(tr("鍵が開いた！ ほかの部屋にも印を付けられる"), systemImage: "lock.open.fill")
                    .scaledFont(14, weight: .heavy, design: .rounded)
                    .foregroundStyle(Theme.tealText)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            } else if showsKeyLockedHint {
                Label(tr("先に鍵の猫を見つけよう"), systemImage: "lock.fill")
                    .scaledFont(14, weight: .heavy, design: .rounded)
                    .foregroundStyle(Theme.coralText)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            } else if showsHintUsedUp {
                Label(tr("この局のヒントは使い切りました"), systemImage: "lightbulb.slash")
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
                    .multilineTextAlignment(.center)
            } else if let hint = model.lastHint {
                Label(CatPuzzleAccessibility.message(for: hint, puzzle: model.puzzle, roomName: { CatPuzzleHouse.room($0).name }),
                      systemImage: "lightbulb.fill")
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.yellowText)
                    .multilineTextAlignment(.center)
            } else if model.isKeyLocked {
                Label(tr("鍵の猫を探そう（金色の枠の部屋だけ触れる）"), systemImage: "key.fill")
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.yellowText)
                    .multilineTextAlignment(.center)
            } else {
                Text(tr("タップで × を付け外し。ダブルタップでそのマスの猫を見つけます。"))
                    .scaledFont(14, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minHeight: 36)
    }

    /// 終局のおじさんの一言（顔＋横いっぱいの吹き出し）。
    private func ojisanLine(face: OjisanPixel.Face, text: String) -> some View {
        HStack(spacing: 10) {
            OjisanPixel.faceImage(face)
                .frame(width: 40, height: 37.5)
            Text(text)
                .scaledFont(16, weight: .bold, design: .rounded, maxScale: 1.4)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .popCard(corner: Theme.cornerSmall)
        }
        .frame(maxWidth: .infinity)
    }

    /// 盤の下の操作（#148・#1689）。遊んでいる間はヒント・戻す・⋯、終局（クリア・ミス 3 回の負け）したら他のゲームと同じ
    /// 「同じ条件でもう一回」「設定を変える」（`GameReplayBar`）とレコメンドに替える（会長 QA 2026-10-21・build 42）。
    ///
    /// 遊んでいる間は操作の段の高さだけを取り、決着後の段（もう一回＋レコメンド）の高さは確保しない（#3048）。
    /// 確保すると SE で盤が 216pt まで縮み、段の下に画面の 1/4 ほどの空きが残っていた。入れ替えは結果カードを
    /// 画面全体に出している間（クリアのカード・ミス 3 回のカード）に行い、盤の大きさが変わる瞬間を見せない
    /// （`showsFinishedControls`）。
    @ViewBuilder var controlArea: some View {
        if Self.showsFinishedControls(model) {
            GameControlArea(isFinished: true, services: services, ladder: model.stage == nil ? ladder : nil) {
                if let stage = model.stage, model.isSolved {
                    CatPuzzleNextStageBar(next: stage + 1,
                                          onNext: { startStage(stage + 1) },
                                          onChangeSettings: { showNewGame = true })
                } else {
                    GameReplayBar(
                        onReplay: { replay() },
                        onChangeSettings: { showNewGame = true }
                    ) {
                        RecordLabel(shownRecord)
                    }
                }
            } playing: {
                EmptyView()
            }
        } else {
            let controls = Self.playControls(
                for: model,
                isWatchingAd: hintRescue.isWatching || teachRescue.isWatching,
                onClear: { showConfirmClear = true },
                onUndo: { withGameAnimation { model.undo() } },
                onHint: { requestHint() },
                onTeach: { Self.requestTeach(model: model, teachRescue: teachRescue, services: services) }
            )
            if !controls.menu.isEmpty || !controls.actions.isEmpty {
                GameOverflowBar(menuItems: controls.menu, actions: controls.actions, verticalPadding: 4)
            }
        }
    }

    /// 決着後の段に替えるか。クリアはカードが出た時点（最後の猫から 1 拍後）、ミス 3 回は提案のカードが出た時点で替える
    /// （どちらもカードが画面全体を覆っている間に盤の大きさが変わる）。コンティニューで戻ったら遊ぶ段に戻る。
    static func showsFinishedControls(_ model: CatPuzzleModel) -> Bool {
        model.showsClearCard || model.isFailed || model.isOfferingContinue
    }

    /// 遊んでいる間の操作の段（#1834）。広告が絡むヒントと「戻す」を段に、やり直しは「⋯」に入れる。
    /// 終局した後は何も返さない（終局後は `GameReplayBar` に替わる）。
    static func playControls(
        for model: CatPuzzleModel,
        isWatchingAd: Bool = false,
        onClear: @escaping () -> Void = {}, onUndo: @escaping () -> Void = {}, onHint: @escaping () -> Void = {},
        onTeach: @escaping () -> Void = {}
    ) -> (menu: [GameControlMenuItem], actions: [GameActionItem]) {
        guard !model.isOver else { return ([], []) }
        let menu = [
            GameControlMenuItem(
                id: "clear", title: tr("やり直し"), systemImage: "arrow.counterclockwise",
                isDestructive: true, isEnabled: model.hasProgressToLose && !model.isOfferingContinue && !isWatchingAd, action: onClear
            ),
        ]
        // ステージでは「戻す」をやめて「餌をあげる」（解析の purpose は `teach` のまま）にする（#3203）。自由に遊ぶは従来どおり「戻す」。
        let second = model.stage == nil
            ? GameActionItem(
                id: "undo", title: tr("戻す"), systemImage: "arrow.uturn.backward", role: .undo,
                isEnabled: model.canUndo && !isWatchingAd, action: onUndo
            )
            : GameActionItem(
                id: "teach", title: tr("餌をあげる"), systemImage: "fork.knife", role: .undo,
                badge: teachBadge(for: model),
                isEnabled: model.canTeach && !isWatchingAd,
                accessibilityLabel: model.needsAdForTeach
                    ? tr("餌をあげる、無料の回数は使い切りました。広告を見ると1回追加")
                    : tr("餌をあげる、あと%lld回", model.teachRemaining),
                accessibilityHint: tr("餌で猫を1匹おびき出して、正解のマスに置きます。置いた猫は消せません"),
                action: onTeach
            )
        let actions = [
            second,
            GameActionItem(
                id: "hint", title: tr("ヒント"), systemImage: "lightbulb.fill", role: .hint,
                badge: hintBadge(for: model),
                // 上限まで使い切ったら押せない見た目にするが、押すと「使い切りました」と知らせる（広告は出さない・#3048）。
                isEnabled: (model.canHint || isHintUsedUp(model)) && !isWatchingAd,
                looksDisabled: isHintUsedUp(model),
                accessibilityLabel: CatPuzzleAccessibility.hintLabel(remaining: model.hintsRemaining, needsAd: model.needsAdForHint),
                accessibilityHint: isHintUsedUp(model)
                    ? tr("この局のヒントは使い切りました")
                    : tr("推理の1歩を示します。確実に猫のいないマスに×を置き、確定するときだけ猫を置きます"),
                action: onHint
            ),
        ]
        return (menu, actions)
    }

    /// ヒントの 2 行目。「あと n 回」は無料ぶんだけで、使い切ったら「0回 ▶ 広告を見て +1」の面にする
    /// （15パズル・将棋などと同じ `GameActionBadge.hint`。広告の追加まで使い切ったら 0 のまま・#1897）。
    /// 広告で足せる上限は盤ゲームの 5 回ではなく 3 回なので、それを渡す（#3048）。
    static func hintBadge(for model: CatPuzzleModel) -> GameActionBadge {
        // ステージは全ステージ共通の残り。0 なら広告 1 回で 1 回（何度でも）。
        if model.stage != nil { return model.needsAdForHint ? .ad() : .count(model.hintsRemaining) }
        return .hint(totalRemaining: model.hints.remaining, needsAd: model.needsAdForHint, adLimit: model.hints.adLimit)
    }

    /// 無料と広告の追加を合わせて、この局のヒントを上限まで使い切ったか（遊んでいる間だけ）。
    static func isHintUsedUp(_ model: CatPuzzleModel) -> Bool {
        model.stage == nil && model.hints.isExhausted && !model.isOver && !model.isOfferingContinue
    }

    /// 無料が残っていればそのまま示し、使い切っていれば広告を見たあとに示す（広告は押下起点・自動再生しない）。
    /// 上限まで使い切っていたら広告は出さず、盤の下に「この局のヒントは使い切りました」を数秒出す。
    private func requestHint() {
        if Self.isHintUsedUp(model) {
            showsHintUsedUp = true
            AccessibilityNotification.Announcement(tr("この局のヒントは使い切りました")).post()
            return
        }
        Self.requestHint(model: model, hintRescue: hintRescue, services: services)
    }

    /// `requestHint()` の中身（テストからモックの services で広告の成功・失敗を確かめるため static にしている）。
    /// どの局に対する広告かを出す前に控え、ロード中に始めた新しい局へは乗せない（15パズル・ナンプレのヒントと同じ #815）。
    static func requestHint(model: CatPuzzleModel, hintRescue: RewardedRescue, services: GameServices) {
        guard !hintRescue.isWatching, model.canHint else { return }
        guard model.needsAdForHint else {
            withGameAnimation { model.useHint() }
            return
        }
        let game = model.gameSerial
        hintRescue.request(
            services, gameID: CatPuzzleModel.gameID, purpose: .hint,
            guardedBy: .checkedByGrant
        ) {
            // 広告を見たのに入らなかったら黙って終わらせない（`grantAdHint` が false → 「出せませんでした」）。
            withGameAnimation { model.grantAdHint(forGame: game) }
        }
    }

    /// 「餌をあげる」の 2 行目（ヒントと同じ作法。ステージだけ）。
    static func teachBadge(for model: CatPuzzleModel) -> GameActionBadge {
        model.needsAdForTeach ? .ad() : .count(model.teachRemaining)
    }

    /// 「餌をあげる」を押したとき。無料の残りがあればそのまま置き、0 なら広告を見たあとに置く（ヒントの `requestHint` と同じ局ガード）。
    static func requestTeach(model: CatPuzzleModel, teachRescue: RewardedRescue, services: GameServices) {
        guard !teachRescue.isWatching, model.canTeach else { return }
        guard model.needsAdForTeach else {
            withGameAnimation { model.teachCat() }
            return
        }
        let game = model.gameSerial
        teachRescue.request(
            services, gameID: CatPuzzleModel.gameID, purpose: .teach,
            guardedBy: .checkedByGrant
        ) {
            withGameAnimation { model.grantAdTeach(forGame: game) }
        }
    }

    /// 盤の大きさの呼び名。ステージは「ステージ 3（6×6）」、自由に遊ぶは「ふつう（7×7）」。
    private var boardLabel: String {
        if let stage = model.stage {
            return tr("ステージ %1$lld（%2$@）", stage, model.size.sizeLabel)
        }
        return tr("%1$@（%2$@）", model.size.label, model.size.sizeLabel)
    }

    /// 経過時間の時計を出すか。ステージは秒数を持たないので出さない（#3210）。
    static func showsClock(_ model: CatPuzzleModel) -> Bool { model.stage == nil }

    /// クリアのカードの行。SE の画面に収まるよう 2〜3 行に詰める（#3048。以前は 5 行で盤からはみ出しスクロールになっていた）。
    /// ヒントは 0 回でも省かず出す（#2613・#2801）。ステージはタイムを出さない（#3210）。
    var clearDetails: [String] {
        var lines: [String]
        if model.stage != nil {
            // ステージは進み具合・手数を出さない（#3329。進み具合はステージ選択の画面にある）。
            // 盤の名前・クリアタイム（プレイ中の時計・記録は出さない #3210 のまま）の 2 行。ライフ・ヒント・餌は `clearStats`。
            lines = [boardLabel, tr("クリアタイム %@", RecordFormat.time(model.elapsedSeconds))]
        } else {
            lines = [
                tr("タイム %1$@・ライフ %2$lld・ヒント %3$lld回",
                   RecordFormat.time(model.elapsedSeconds), model.mistakesRemaining, model.hintsUsed),
                tr("%1$@・手数 %2$lld", boardLabel, model.moves),
            ]
        }
        if model.lastEventPoints != nil {
            // イベント開催中のステージは、今日の合計 pt と今日の順位（読めなければ合計 pt だけ。#3329）。
            lines.append(CatPuzzleClearFlow.todayLine(total: model.eventTotal, rank: clearStanding?.rank,
                                                      participants: clearStanding?.participants))
        } else if model.mistakes == 0 {
            lines.append(tr("ミスなしのパーフェクト！"))
        }
        if model.stage != nil, model.noMissStreak >= CatPuzzleNoMiss.showsFrom {
            lines.append(model.beatNoMissBest
                ? tr("ノーミス %lld 面連続・自己ベスト", model.noMissStreak)
                : tr("ノーミス %lld 面連続", model.noMissStreak))
        }
        return lines
    }

    /// ステージのクリアのモーダルに、アイコン付きで出すライフ・ヒント・餌（盤の下のボタンと同じアイコン・#3329）。
    var clearStats: [GameClearCard.Stat] {
        guard model.stage != nil else { return [] }
        return [
            .init(systemImage: "heart.fill", text: tr("ライフ %lld", model.mistakesRemaining)),
            .init(systemImage: "lightbulb.fill", text: tr("ヒント %lld回", model.hintsUsed - model.stageTeachesUsed)),
            .init(systemImage: "fork.knife", text: tr("餌 %lld回", model.stageTeachesUsed)),
        ]
    }

    /// 結果に添える記録の行。ステージの記録は秒数を持たず、共通の 1 行（最短タイム）では「クリア記録なし」に
    /// 化けるので出さない（#3210）。
    private var shownRecord: RecordResult? { Self.showsClock(model) ? model.recordResult : nil }

    /// クリアのカード（画面全体に重ねる）。ステージは見出しを「ステージ n クリア！」にし、「次のステージへ」を置く。
    var clearCard: some View {
        let title = model.stage.map { tr("ステージ %lld クリア！", $0) } ?? tr("クリア！")
        return ZStack {
            Color.black.opacity(0.45)
            if model.stage != nil, !clearFlow.showsModal {
                // 猫のアニメのあと、ライフ → pt → ランキングの順に見せてからモーダル（#3304）。
                CatPuzzleClearFlowCard(
                    step: clearFlow.step, lives: model.mistakesRemaining,
                    isKey: model.lastEventWasKey, total: model.eventTotal,
                    loadBoard: { await loadTodayBoard() },
                    onFinish: { withGameAnimation { clearFlow.advance() } },
                    onResult: { result in clearStanding = result?.rank.map { ($0, result?.board.participants ?? $0) } }
                )
            } else {
            GameClearCard(
                title: title, details: clearDetails, stats: clearStats,
                primaryAction: model.stage.map { stage in
                    GameClearCard.PrimaryAction(
                        title: tr("次のステージへ"),
                        hint: tr("ステージ %lld を始めます", stage + 1)
                    ) { startStage(stage + 1) }
                },
                share: CatPuzzleShare.content(for: model)
            ) {
                clearCardClosed = true
            }
            }
        }
        // ランキングの全画面は領域いっぱいに敷くので、角は丸めない（暗幕が四隅に見えるのを防ぐ）。
        .clipShape(RoundedRectangle(cornerRadius: clearFlow.step == .ranking ? 0 : Theme.corner))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// 今日の順位表（Game Center・上位 10 人）。読めなければ nil（未サインイン・失敗）。
    private func loadTodayBoard() async -> GameCenterBoard? {
        // 送った pt が順位に乗ってから読む。友だちの順位は待たず、盤の順位だけを読む。
        await model.awaitEventSubmission()
        // 送れていないと盤は今日の合計より古い。順位表は出さず、合計だけの表示に戻す。
        guard model.isEventTotalSent() else { return nil }
        guard let reporter = services.gameCenter, reporter.isSignedIn else { return nil }
        guard let board = await reporter.loadWeeklyBoard(
            gameID: CatPuzzleModel.gameID, leaderboardID: GameCenterLeaderboard.catPuzzleEvent,
            topCount: CatPuzzleClearFlow.tableRows
        ) else { return nil }
        return CatPuzzleRankingModel.today(board, now: Date())
    }

    /// 3 回目のミスで出す、ただ 1 枚のダイアログ（他のゲームの負けと同じ `BoardGameResultCard`・#2904）。
    /// 提案中は「広告を見てコンティニュー」でミスが 1 回ぶん戻り、「あきらめて正解を見る」で負けを確定して盤に正解を出す
    /// （負けはあきらめた時点で確定するので、記録の行はこのカードには出ない）。
    /// コンティニュー済みの局は負けが確定した状態で出し、「盤を見る」で閉じる（正解はカードの後ろで盤に出る）。
    /// 補足は 1 行に詰める（#3048。SE で画面の高さぎりぎりだった）。「広告を見ると、ミスが1回ぶん戻ります」は
    /// コンティニューのボタンの読み上げのヒントに残す。
    var failCard: some View {
        let offering = model.isOfferingContinue
        return BoardGameResultCard(
            verdict: .loss,
            reason: tr("%lld回まちがえた…", CatPuzzleModel.maxMistakes),
            details: [Self.showsClock(model) ? tr("%1$@・タイム %2$@", boardLabel, RecordFormat.time(model.elapsedSeconds)) : boardLabel],
            record: offering ? nil : shownRecord,
            secondaryAction: offering
                ? BoardGameResultCard.SecondaryAction(
                    title: tr("広告を見てコンティニュー"),
                    hint: tr("広告を見ると、ライフが1つ戻ります")
                ) { requestContinue() }
                : nil,
            closeTitle: offering ? tr("あきらめて正解を見る") : nil,
            closeHint: offering ? tr("負けを確定して、猫のいる場所を盤に表示します") : nil
        ) {
            if offering {
                withGameAnimation { model.declineContinue() }
            } else {
                failCardClosed = true
            }
        }
    }

    /// ステージの問題を作っている間に盤へ重ねる表示。
    var preparingOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.surface.opacity(0.85))
            VStack(spacing: 10) {
                ProgressView()
                Text(tr("問題を用意しています…"))
                    .scaledFont(15, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
