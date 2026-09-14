import Foundation

/// 横スクロールランナーの中断・記録データ（#494）。
///
/// **フレーム単位の保存はしない**（アクション枠の基盤規約）。走者の位置・速度まで保存すると
/// 保存の粒度がフレームに縛られ、「再開した瞬間に目の前が穴」という理不尽な復帰になる。
/// 保存するのは**ステージの頭の状態**（何面から再開するか）と、**ステージごとのベストタイム**だけ。
///
/// ベストタイムを同じファイルに入れているのは、保存先を 2 つに増やさないため。
/// 大きさは**ステージ数ぶんで固定**（`RunnerRules.stageCount` 件）で、遊ぶほど増えることはない。
public struct RunnerSnapshot: Codable, Equatable, Sendable {
    /// 再開するステージ番号（1 始まり）。
    public var stage: Int
    /// ステージごとのベストタイム（秒）。要素数はステージ数ぶんで、**0 は未クリア**。
    ///
    /// 添字 0 がステージ 1。辞書ではなく配列なのは、鍵の型で JSON の形が変わるのを避けるため。
    public var bestSeconds: [Int]
    /// 到達した最大のステージ番号（1 始まり・#798）。ワールドマップで選べる面の上限。
    ///
    /// `stage` は「次に開いたときどこから再開するか」で、面を選んで遊ぶと選んだ面へ動く。
    /// それとは別に「どこまで進んだことがあるか」をここに持ち、面を選んで遊んでも巻き戻さない。
    /// **optional の鍵**にしてあるのは、v1.1.4 以前の中断データ（この鍵が無い）を読めなくしないため
    /// （非 optional にすると復号が失敗して中断ごと消える）。nil なら `stage` を到達点とみなす。
    public var reachedStage: Int?

    public init(stage: Int, bestSeconds: [Int], reachedStage: Int? = nil) {
        self.stage = stage
        self.bestSeconds = bestSeconds
        self.reachedStage = reachedStage
    }

    /// 復元して使える内容か検める。
    ///
    /// `[Int]` は JSON からいくらでも別の長さで読めてしまうので「復号できた = 遊べる」ではない
    /// （#520 と同じ考え方）。長さが違えば足りないぶんを 0 で埋め、余りは捨てる。
    /// 到達しえない値（負・上限超え）は壊れたデータとして丸める。
    /// 到達ステージ（#798）は再開面より前にはならない（鍵の無い旧データは再開面をそのまま
    /// 到達点にする。上限超えは最終面に丸める）。
    public func validated() -> (stage: Int, bestSeconds: [Int], reachedStage: Int)? {
        guard stage >= 1, stage <= RunnerRules.stageCount else { return nil }
        let reached = min(max(stage, reachedStage ?? stage), RunnerRules.stageCount)
        var times = Array(bestSeconds.prefix(RunnerRules.stageCount))
        // 想定しえないタイムは 0（未クリア）に倒す。負の値をそのまま最短記録にすると
        // 二度と更新できない自己ベストになる。
        times = times.map { (0...Self.maxSeconds).contains($0) ? $0 : 0 }
        times += Array(repeating: 0, count: max(0, RunnerRules.stageCount - times.count))
        return (stage, times, reached)
    }

    /// 記録として受け付けるタイムの上限（秒）。最長のステージでも 1 分に届かない。
    static let maxSeconds = 60 * 60
}
