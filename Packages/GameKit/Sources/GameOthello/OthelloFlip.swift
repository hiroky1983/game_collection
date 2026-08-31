import Foundation

/// 石が裏返る演出の長さと形（#204）。**状態を持たない定数と純関数だけ**を置き、View から切り出す。
///
/// 盤は `Canvas` 1 つに石を直接描いているため、外から `.gameAnimation` を掛けただけでは
/// 色が瞬間で入れ替わるだけになる（`Canvas` はビュー本体が作り直されない限り描き直されない）。
/// 五目並べ（#202）と同じく盤の `Canvas` を `Animatable` にして進捗を補間させ、その進捗を
/// ここの純関数で「どの石が・どこまで返ったか」に翻訳する。切り出しておけば
/// `OthelloFlipTests` でシミュレータを立てずに固定できる。
///
/// Reduce Motion が ON のときは `.gameAnimation` がアニメーションを落とすため補間が起きず、
/// 進捗は常に 1（= 返り終わった状態）になる。従来どおりの即時反映に戻るだけで、盤は壊れない。
public enum OthelloFlip {

    /// 置いた石のまわりが返り始めてから、最も遠い石が返りきるまでの長さ（秒）。
    ///
    /// 短すぎると何が起きたか目で追えず、長いと CPU の着手が遅れる（受け入れ条件3）。
    public static let duration: TimeInterval = 0.36

    /// 石 1 枚が返るのに使う区間の長さ（全体の進捗に対する割合）。
    public static let span: Double = 0.6

    /// 置いた石から 1 マス遠いごとに反転の開始が遅れる割合（全体の進捗に対する割合）。
    ///
    /// 内側から外側へ順に返すことで、複数方向へ同時に返る局面でも「どの方向に何枚返ったか」を
    /// 追える（受け入れ条件2）。オセロで一方向に返る枚数は最大 6 枚（8×8 の端から端）なので、
    /// 最も遠い石でも `stagger * 5 + span == 1.0` とちょうど全体の進捗に収まる。
    public static let stagger: Double = 0.08

    /// 反転中の石が完全に消えないよう残す最小の幅（実寸に対する割合）。
    public static let minimumWidthScale: Double = 0.06

    /// 全体の進捗から、置いた石から `distance` マス離れた石の進捗（0→1）を求める。
    ///
    /// - Parameter distance: 置いた石とのチェビシェフ距離（`max(|Δ行|, |Δ列|)`）。
    ///   同じ方向に連なる石はこの距離が 1, 2, 3… と増えるので、そのまま順番になる。
    public static func progress(distance: Int, overall: Double) -> Double {
        // 距離が想定より大きくても区間が盤の外（1 超）へ出ないよう頭打ちにする。
        let start = min(Double(max(distance - 1, 0)) * stagger, 1 - span)
        return min(max((overall - start) / span, 0), 1)
    }

    /// 反転中に見えている石の色。
    ///
    /// - Parameter target: 返り終わったあとの色。モデルの盤はすでに着手を反映済みなので、
    ///   前半（真横を向く手前）では反対の色を描く。
    public static func shownStone(target: OthelloStone, progress: Double) -> OthelloStone {
        progress < 0.5 ? target.opponent : target
    }

    /// 反転中の石の横幅（実寸に対する割合）。
    ///
    /// 円盤を縦軸まわりに回すので幅は `|cos(πp)|` になる。真横を向く `p = 0.5` で 0 まで
    /// 落とすと石が一瞬消えて見えるため、薄い縁として `minimumWidthScale` を残す。
    public static func widthScale(progress: Double) -> Double {
        max(abs(cos(.pi * progress)), minimumWidthScale)
    }
}
