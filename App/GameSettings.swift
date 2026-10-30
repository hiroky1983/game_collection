import Foundation
import Observation
import Core
import GameRunner
import GameBlocks
import GameHomerun

@MainActor
@Observable
final class GameSettings {
    private(set) var orderedIDs: [String]
    private(set) var hiddenIDs: Set<String>
    /// 現在登録されているゲームの ID（登録順）。並びを初期に戻すときの基準（#3006）。
    private let registeredIDs: [String]
    /// 触覚フィードバックのオン / オフ。既定はオン。
    var hapticsEnabled: Bool {
        didSet { Self.haptics.isEnabled = hapticsEnabled }
    }
    /// 効果音のオン / オフ。既定はオン。触覚とは独立に切り替えられる。
    var soundEnabled: Bool {
        didSet { Self.sound.isEnabled = soundEnabled }
    }
    /// 効果音の音量（小・中・大・#3007）。既定は中。効果音がオンのときに全ゲームの音へ効く。
    var soundVolume: SoundVolume {
        didSet { Self.soundVolumePreference.volume = soundVolume }
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
    /// **切り替えは設定画面からのみ**（#631）。以前はゲーム内の一時停止画面からも
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
    /// ゆっくりモードを切り替えると消える中断データが、いま残っているか（#3107）。
    /// 設定画面が、残っているときだけ切り替え前に確認を出すために読む。
    var slowModeToggleDiscardsSnapshots: Bool {
        // 「続きから」の判定ではなく、破棄されるものがあるかの有無なので、生の `exists` で見てよい。
        // （ハブの走査テスト #809 が `snapshots.exists(` の直書きを禁じるため、変数名は `store`）
        let store = AppEnvironment.services.snapshots
        return store.exists(for: RunnerModel.gameID) || store.exists(for: BlocksModel.gameID)
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
    /// 通知のオン / オフ（#1508）。既定はオン。
    /// 「続きのお知らせ」（#663）と「久しぶり通知」（#1193）は判定条件・予約ロジックは別のまま、
    /// 設定画面のトグルと保存値はこの1つにまとめている。オフにした時点で両方の予約済みの
    /// お知らせを取り消す（オフにしたのに翌日届く、を作らない）。
    var notificationsEnabled: Bool {
        didSet {
            Self.notifications.isEnabled = notificationsEnabled
            Self.reengagementReminders.isEnabled = notificationsEnabled
            if !notificationsEnabled {
                AppEnvironment.reminders.cancelAll()
                AppEnvironment.reengagement.cancelAll()
                AppEnvironment.returnReminder.cancel()
            }
        }
    }

    private static let orderKey    = "gameOrder_v1"
    private static let hiddenKey   = "hiddenGames_v1"
    /// 柵越えおじさんを保存済みの並びの先頭へ一度だけ移したか（#2572）。
    private static let homerunFrontKey = "gameOrderHomerunFront_v1"
    private static let haptics = FeedbackPreference(key: "hapticsEnabled_v1")
    private static let sound   = FeedbackPreference(key: "soundEnabled_v1")
    private static let soundVolumePreference = SoundVolumePreference()
    // 触覚・効果音と同じ「未設定ならオン」の箱に相乗りする（新しい永続化の仕組みを増やさない）。
    private static let analytics = FeedbackPreference(key: "analyticsEnabled_v1")
    private static let notifications = FeedbackPreference(key: "resumeRemindersEnabled_v1")
    private static let reengagementReminders = FeedbackPreference(key: "reengagementRemindersEnabled_v1")
    // ヒント表示はゲーム側（GameKit）も同じキーを読むため、定義は Core に置いたものを共有する。
    private static var hints: FeedbackPreference { .hints }
    // ゆっくりモード（#463・#494）も同じ理由で Core 側の定義を共有する。既定値だけがオフ。
    private static var slowMode: FeedbackPreference { .actionSlowMode }

    init(registeredIDs: [String]) {
        self.registeredIDs = registeredIDs
        let stored = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
        self.orderedIDs = GameOrderMerge.mergedOrder(stored: stored, registered: registeredIDs)

        let hiddenArr = UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []
        self.hiddenIDs = GameOrderMerge.mergedHidden(stored: hiddenArr, registered: registeredIDs)

        // 未設定（初回起動・キー無し）はオン。既定値の規則は FeedbackPreference が持つ。
        self.hapticsEnabled = Self.haptics.isEnabled
        self.soundEnabled = Self.sound.isEnabled
        self.soundVolume = Self.soundVolumePreference.volume
        self.analyticsEnabled = Self.analytics.isEnabled
        let mergedNotificationsEnabled = NotificationsPreferenceMerge.mergedIsEnabled(
            resume: Self.notifications.isEnabled,
            reengagement: Self.reengagementReminders.isEnabled
        )
        self.notificationsEnabled = mergedNotificationsEnabled
        // 統合前に片方だけオフだった保存値を、次回起動時からも一致させておく（didSet は
        // 初期化中の代入では呼ばれないため、ここで明示的に書き戻す）。
        Self.notifications.isEnabled = mergedNotificationsEnabled
        Self.reengagementReminders.isEnabled = mergedNotificationsEnabled
        // 統合前は久しぶり通知だけオフ（続きのお知らせはオン）だった等の場合、統合直後は
        // 予約済みの片方が残ったままになる。didSet が呼ばれない初期化中の代入では取り消しも
        // 走らないため、ここで明示的に両方取り消す。
        if !mergedNotificationsEnabled {
            AppEnvironment.reminders.cancelAll()
            AppEnvironment.reengagement.cancelAll()
            AppEnvironment.returnReminder.cancel()
        }
        self.hintsEnabled = Self.hints.isEnabled
        self.slowModeEnabled = Self.slowMode.isEnabled

        // 柵越えおじさんは #2566 で通常のタイルになるまで、並びとは無関係に常に先頭の特別枠だった。
        // 並べ替え・非表示をしたことのある端末は保存済みの並びの中で末尾近く（v1.1.9 で足されたとき
        // の位置）にあり、通常のタイルになった版でそのまま末尾へ落ちた（#2572・会長 QA 2026-10-20）。
        // 以前と同じ先頭へ一度だけ移す（ほかのゲームの相対順はそのまま。以後の並べ替えは利用者の自由）。
        // 保存が無い端末は登録順（先頭が柵越えおじさん）なので動かない。
        if !UserDefaults.standard.bool(forKey: Self.homerunFrontKey) {
            let promoted = GameOrderMerge.promotingToFront(orderedIDs, id: HomerunModel.gameID)
            if promoted != orderedIDs {
                orderedIDs = promoted
                save()
            }
            UserDefaults.standard.set(true, forKey: Self.homerunFrontKey)
        }
    }

    /// 保存されている設定を読み直す。設定画面を開くたびに呼ぶ（保険。#631でゆっくり
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
            // 非表示にしたゲームのお知らせは届けない。予約済みもこの時点で取り消す（#810）。
            hiddenIDs.insert(id)
            AppEnvironment.reminders.gameDidHide(gameID: id)
        }
        save()
    }

    /// 並びを登録順に、非表示をすべて表示に戻す（#3006）。保存した並びと非表示は消す。
    /// 柵越えおじさんの先頭移動は登録順で先頭になるので、フラグは立てたままでよい。
    func resetToDefault() {
        orderedIDs = registeredIDs
        hiddenIDs = []
        UserDefaults.standard.removeObject(forKey: Self.orderKey)
        UserDefaults.standard.removeObject(forKey: Self.hiddenKey)
    }

    private func save() {
        UserDefaults.standard.set(orderedIDs, forKey: Self.orderKey)
        UserDefaults.standard.set(Array(hiddenIDs), forKey: Self.hiddenKey)
    }
}
