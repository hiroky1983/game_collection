import Foundation
import Core

public enum SolitairePhase: String, Codable, Sendable, Equatable {
    /// 取り進めている最中。
    case playing
    /// 52 枚すべてを組札に積んだ。
    case won
}

/// 「戻す」の回数制（#476）。無料の初期回数とリワード広告での補充量を 1 か所に持つ。
///
/// **`SolitaireModel` の外に置く**のは、モデルが `@MainActor` なのに対し読み上げ文
/// （`SolitaireAccessibility`）が非隔離の純関数だから。中に静的定数として持つと、
/// 読み上げ側から回数を参照できず文言と実装が二重管理になる。
///
/// 値そのものは `Core.RewardedUndoBudget` が持つ（#492 でフリーセルと共有するため Core へ上げた）。
/// ここは呼び出し側の表記をソリティアの文脈に残すための転送で、**両ゲームの経済は常に一致する**。
public enum SolitaireUndoBudget {
    /// 1 局につき無料で戻せる回数。配り直し・新規ゲームでここまで戻る。
    public static let free = RewardedUndoBudget.free
    /// リワード広告 1 本の視聴完了で補充する回数。
    public static let refill = RewardedUndoBudget.refill
}

/// いま持ち上げている札。
///
/// 場札は「その位置から上を丸ごと」動かすため、列と `faceUp` の添字の組で表す。
public enum SolitaireSelection: Equatable, Sendable {
    case waste
    case tableau(pile: Int, cardIndex: Int)
}

/// 中断スナップショット。
///
/// **配札は種から決定的に再現できる**（`SolitaireDealer.deal`）ので、盤面そのものは保存せず
/// 「種 + 指した手順」だけを持つ。undo も同じ手順の再生で実現しているため、保存と巻き戻しの
/// 経路が 1 本にまとまる。
struct SolitaireSnapshot: Codable {
    let seed: UInt64
    let moves: [SolitaireMove]
    let elapsedSeconds: Int
    /// この局で受け取ったジョーカーの累計枚数（初期 1 枚 + リワード広告での補充・#406）。
    ///
    /// **所持は手順から導出できない**（広告を見た事実が `moves` に残らない）ので、ここだけは
    /// 別に持つ。所持枚数そのものではなく「累計で何枚もらったか」を持つのは、undo で
    /// 置いた手を戻したときに所持へ自然に返す（#397 吟味2）ため — 所持は
    /// 「もらった枚数 − 置いた枚数」として毎回導出する。
    ///
    /// **省略可**。ジョーカーが存在しなかった版の中断データには入っていないので、欠けていたら
    /// 初期 1 枚だけもらった扱いにする（旧データを再開しても救済が使える）。
    let jokerGrants: Int?
    /// 「戻す」の残り回数（#476）。
    ///
    /// **手順から導出できない**（消費も広告での補充も `moves` に残らない）ので、ジョーカーと
    /// 同じくここだけは別に持つ。ジョーカーが「累計でもらった枚数」なのに対しこちらが残数
    /// そのものなのは、undo の消費が単調で「戻すの undo」が存在しないため。
    ///
    /// **省略可**。回数制が無かった版の中断データには入っていないので、欠けていたら
    /// 無料枠が丸ごと残っている扱いにする（再開した局が理不尽に戻せなくならない）。
    let undosRemaining: Int?
    /// この局に焼き込んだめくり枚数（#498。`SolitaireDrawMode.rawValue`）。
    ///
    /// **省略可**。分岐が無かった版の中断データには入っていないので、欠けていたら
    /// 1 枚めくり（分岐が存在しなかった頃のルール）に倒す。非 optional にすると
    /// 旧データのデコードが丸ごと失敗し、中断が黙って消える（`docs/ai-devops.md` 規約2）。
    let drawMode: String?
}
