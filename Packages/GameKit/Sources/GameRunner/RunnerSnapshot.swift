import Foundation

/// 横スクロールランナーの中断・記録データ（#494）。
///
/// **フレーム単位の保存はしない**（アクション枠の基盤規約）。走者の位置・速度まで保存すると
/// 保存の粒度がフレームに縛られ、「再開した瞬間に目の前が穴」という理不尽な復帰になる。
/// 保存するのは**ステージの頭の状態**（何面から再開するか）と、**どこまで到達したか**だけ。
///
/// 大きさは固定（遊ぶほど増えることはない）。
public struct RunnerSnapshot: Codable, Equatable, Sendable {
    /// 再開するステージ番号（1 始まり）。
    public var stage: Int
    /// **旧形式の名残**。v1.1.4 まではステージごとのベストタイム（秒）をここに持っていたが、
    /// 秒数は要素として廃止した（#931・会長決裁「ステージのタイムは要らない」）。
    ///
    /// 鍵を残してあるのは、**旧データを読めなくしないため**（鍵を消すと旧データの復号は通るが、
    /// 新データを旧版が読むと落ちる。どちら向きにも壊さない）。読んだ値は使わず、
    /// 書くときは空配列にする。
    public var bestSeconds: [Int]
    /// 到達した最大のステージ番号（1 始まり・#798）。ワールドマップで選べる面の上限。
    ///
    /// `stage` は「次に開いたときどこから再開するか」で、面を選んで遊ぶと選んだ面へ動く。
    /// それとは別に「どこまで進んだことがあるか」をここに持ち、面を選んで遊んでも巻き戻さない。
    /// **optional の鍵**にしてあるのは、v1.1.4 以前の中断データ（この鍵が無い）を読めなくしないため
    /// （非 optional にすると復号が失敗して中断ごと消える）。nil なら `stage` を到達点とみなす。
    public var reachedStage: Int?

    public init(stage: Int, bestSeconds: [Int] = [], reachedStage: Int? = nil) {
        self.stage = stage
        self.bestSeconds = bestSeconds
        self.reachedStage = reachedStage
    }

    /// 復元して使える内容か検める。
    ///
    /// 到達しえない値（負・上限超え）は壊れたデータとして扱う（#520 と同じ考え方）。
    /// 到達ステージ（#798）は再開面より前にはならない（鍵の無い旧データは再開面をそのまま
    /// 到達点にする。上限超えは最終面に丸める）。旧形式のベストタイム（`bestSeconds`）は
    /// 長さ・値に関わらず読み捨てる。
    public func validated() -> (stage: Int, reachedStage: Int)? {
        guard stage >= 1, stage <= RunnerRules.stageCount else { return nil }
        let reached = min(max(stage, reachedStage ?? stage), RunnerRules.stageCount)
        return (stage, reached)
    }
}
