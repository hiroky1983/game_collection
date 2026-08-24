import CoreGraphics

/// マインスイーパーの寸法と演出の長さ。**状態を持たない純粋な定数・関数**として View から切り出す（#203）。
///
/// 切り出す理由は麻雀ソリティア（`MahjongSolitaireBoardMetrics`・#196/#197）と同じで、
/// 「押しにくい」「何が起きたか見えない」の急所がソースに散らばった数値のままだと
/// シミュレータを立てるまで退行に気づけないため。ここに集約すればテストで固定できる。
enum MinesweeperMetrics {

    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 旗モード・拡大モードの切り替えボタンの一辺の下限（#203）。
    ///
    /// 従来はアイコン 13pt + 左右 8pt・上下 5pt の余白で実測およそ 29×23pt しかなく、
    /// HIG を大きく下回っていた。麻雀ソリティアの表示切り替え（#197）と同じ基準に揃える。
    static let toggleButtonMinSide: CGFloat = minimumTapTarget

    /// ステータスバーの上下の余白（#203）。
    ///
    /// 44pt のボタンが帯の高さを決めるようになるぶん余白を 8 → 4 に詰め、
    /// #148 で盤面に捻出した高さをほぼ据え置きにする（#197 の麻雀ソリティアと同じ手当て）。
    static let statusBarVerticalPadding: CGFloat = 4

    // MARK: - 連鎖開放の演出（#203）

    /// 1 マスの蓋が外れきるまでの長さ（秒）。
    static let revealDuration: Double = 0.16

    /// 連鎖が 1 波進むごとに増える遅延（秒）。
    ///
    /// 波はタップ地点からの Chebyshev 距離（`MinesweeperModel.floodReveal` の BFS の深さ）。
    /// 同じ波のマスは同時に開くので、広がっていく向きが目で追える。
    static let revealWaveStep: Double = 0.035

    /// 連鎖全体に掛けてよい遅延の上限（秒）。
    ///
    /// 上級（15×15）では波が 20 を超えうるため、素直に掛け算すると最後のマスが開くまで
    /// 0.7 秒以上待たされ、次のタップが利かない時間ができる。上限を置くことで
    /// **盤面全体が開くケースでも待ち時間が伸び続けない**（#203 の受け入れ条件3）。
    /// 上限に達したあとの波は同時に開くだけで、追加の計算も待ち時間も発生しない。
    static let revealMaxDelay: Double = 0.35

    /// 連鎖の第 `wave` 波のマスに掛ける遅延（秒）。
    ///
    /// `wave` が 0（タップしたマス自身・地雷の一斉公開）なら遅延なしで即座に開く。
    static func revealDelay(forWave wave: Int) -> Double {
        guard wave > 0 else { return 0 }
        return min(Double(wave) * revealWaveStep, revealMaxDelay)
    }
}
