/// ルーレットの画面の切り替え（#2364）。**View から切り出した純関数**として置き、遷移をテストで固定する。
///
/// 会長決裁（2026-10-17）で「賭けている間は A（大きなホイール + 賭けの表をタブで切り替え）、
/// 回すと B（ホイールを画面いっぱいに出して回し、結果を見せてから賭けの画面へ戻る）」の組み合わせにした。
/// どちらの画面を出すかは Model の局面だけで決まり、Model 側の遷移（`spin` / `settle` / `nextRound` /
/// `repeatLastBets`）には手を入れない。
enum RouletteScreen: Equatable {
    /// 賭けの画面（A）。ホイールは余った高さいっぱい、賭けの表はタブで切り替える。
    case betting
    /// ホイールが主役の画面（B）。回転中・結果・チップ切れはこちら。
    case wheel

    /// 局面からどちらの画面を出すか。
    ///
    /// - 賭け中（`.betting`）は賭けの画面。ただしチップが尽きたら置けないので、ホイールの画面に
    ///   チップ切れの操作欄を出す（復元直後に残高が最低額に届かなかったときもここ）。
    /// - 回転中・結果はホイールの画面。結果から賭けの画面へは「同じ賭けでもう一度」「次のゲーム」を
    ///   押して戻る（どちらも Model を `.betting` に戻す）。
    static func of(phase: RoulettePhase, sessionOver: Bool) -> RouletteScreen {
        phase == .betting && !sessionOver ? .betting : .wheel
    }
}

/// 賭けの画面の表のタブ（#2364・案 A）。
enum RouletteBetTab: CaseIterable, Equatable {
    /// 0〜36 の数字 1 点。
    case numbers
    /// 12 個ずつの区分と、赤黒・奇数偶数・1〜18 / 19〜36。
    case outside

    /// このタブの表に並ぶ賭けか。タブの見出しに「置いている額」を出すのに使う。
    func contains(_ kind: RouletteBetKind) -> Bool {
        switch kind {
        case .straight: return self == .numbers
        default:        return self == .outside
        }
    }
}
