import Foundation
import Observation
import Core
import GameRunner
import GameBlocks

@MainActor
@Observable
final class GameSettings {
    private(set) var orderedIDs: [String]
    private(set) var hiddenIDs: Set<String>
    /// 触覚フィードバックのオン / オフ。既定はオン。
    var hapticsEnabled: Bool {
        didSet { Self.haptics.isEnabled = hapticsEnabled }
    }
    /// 効果音のオン / オフ。既定はオン。触覚とは独立に切り替えられる。
    var soundEnabled: Bool {
        didSet { Self.sound.isEnabled = soundEnabled }
    }
    /// ヒント表示のオン / オフ（#190）。既定はオン。
    /// 大富豪の「いま出せるカードの強調」「出せない理由の1行表示」がこれで切り替わる。
    var hintsEnabled: Bool {
        didSet { Self.hints.isEnabled = hintsEnabled }
    }
    /// アクション枠の「ゆっくりモード」（#463・#494）。**既定はオフ**。
    ///
    /// 反射神経を使うアクション枠は VoiceOver で代替できないため、進みを遅くする手段を
    /// アクセシビリティの代替として置いている（アクション枠の基盤規約）。
    /// ブロック崩しと横スクロールランナーで**1 つの設定を共有する**。
    ///
    /// **切り替えは設定画面からのみ**（#630）。以前はゲーム内の一時停止画面からも
    /// 切り替えられたが、難所の直前で止めてオンにする→通過後にオフへ戻す、を繰り返す
    /// だけでベストタイムをいくらでも作り込めてしまい、アクセシビリティの代替手段の
    /// つもりが難易度調整の抜け道になっていた（会長QA 2026-09-11）。
    ///
    /// 切り替えるたびに**両ゲームの中断データを破棄する**。一時停止中の状態を残したまま
    /// 設定画面へ迂回してモードだけ変える、という間接的な抜け道も塞ぐため。
    var slowModeEnabled: Bool {
        didSet {
            guard oldValue != slowModeEnabled else { return }
            Self.slowMode.isEnabled = slowModeEnabled
            AppEnvironment.services.snapshots.clear(for: RunnerModel.gameID)
            AppEnvironment.services.snapshots.clear(for: BlocksModel.gameID)
        }
    }
    /// 解析送信のオン / オフ（#158）。既定はオン。
    /// オフのあいだ `logEvent` は呼ばれず、Firebase の自動収集イベントも止まる。
    var analyticsEnabled: Bool {
        didSet {
            Self.analytics.isEnabled = analyticsEnabled
            // 明示イベントだけでなく SDK 全体の収集を切り替える（PR #162 の CodeRabbit 指摘）。
            AppEnvironment.applyAnalyticsCollectionState()
            // 設定をまたいだプレイは game_start / game_end の対応が取れないため、
            // 切り替えた時点で進行中の数え方も捨てる（#212）。
            AppEnvironment.analytics.discardPlayState()
        }
    }

    private static let orderKey    = "gameOrder_v1"
    private static let hiddenKey   = "hiddenGames_v1"
    private static let haptics = FeedbackPreference(key: "hapticsEnabled_v1")
    private static let sound   = FeedbackPreference(key: "soundEnabled_v1")
    // 触覚・効果音と同じ「未設定ならオン」の箱に相乗りする（新しい永続化の仕組みを増やさない）。
    private static let analytics = FeedbackPreference(key: "analyticsEnabled_v1")
    // ヒント表示はゲーム側（GameKit）も同じキーを読むため、定義は Core に置いたものを共有する。
    private static var hints: FeedbackPreference { .hints }
    // ゆっくりモード（#463・#494）も同じ理由で Core 側の定義を共有する。既定値だけがオフ。
    private static var slowMode: FeedbackPreference { .actionSlowMode }

    init(registeredIDs: [String]) {
        let stored = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
        var order = stored.filter { registeredIDs.contains($0) }
        for id in registeredIDs where !order.contains(id) { order.append(id) }
        self.orderedIDs = order

        let hiddenArr = UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []
        self.hiddenIDs = Set(hiddenArr.filter { registeredIDs.contains($0) })

        // 未設定（初回起動・キー無し）はオン。既定値の規則は FeedbackPreference が持つ。
        self.hapticsEnabled = Self.haptics.isEnabled
        self.soundEnabled = Self.sound.isEnabled
        self.analyticsEnabled = Self.analytics.isEnabled
        self.hintsEnabled = Self.hints.isEnabled
        self.slowModeEnabled = Self.slowMode.isEnabled
    }

    /// 保存されている設定を読み直す。設定画面を開くたびに呼ぶ（保険。#630でゆっくり
    /// モードの変更経路を設定画面のみに一本化した後も、他の設定同様に保存値との
    /// 食い違いが起きないことを保証しておく）。
    func refreshFromDefaults() {
        slowModeEnabled = Self.slowMode.isEnabled
    }

    func visibleModules(from registry: GameRegistry) -> [GameModule] {
        orderedIDs
            .compactMap { registry.module(id: $0) }
            .filter { !hiddenIDs.contains($0.id) }
    }

    func move(from: IndexSet, to: Int) {
        orderedIDs.move(fromOffsets: from, toOffset: to)
        save()
    }

    func toggleHidden(_ id: String) {
        if hiddenIDs.contains(id) {
            hiddenIDs.remove(id)
        } else {
            hiddenIDs.insert(id)
        }
        save()
    }

    private func save() {
        UserDefaults.standard.set(orderedIDs, forKey: Self.orderKey)
        UserDefaults.standard.set(Array(hiddenIDs), forKey: Self.hiddenKey)
    }
}
