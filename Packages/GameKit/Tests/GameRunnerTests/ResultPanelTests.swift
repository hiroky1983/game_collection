import GameKitTestSupport
import Testing
@testable import GameRunner

/// エンドレスの自己ベスト更新の判定（#839）。
///
/// 0 m で終わる回は冒頭の固定区画（`RunnerEndlessCourse.intro`）があるので実プレイでは作れず、
/// モデル経由では組めない。判定を純関数で固定する（1 m 以上の初回が更新になることは
/// `EndlessCourseTests` がモデル経由で見ている）。
@Suite("チャリンコおじさん エンドレスの自己ベスト判定")
struct RunnerBestDistanceTests {
    @Test("記録が無い状態で 0 m は更新にならず、1 m 以上なら更新")
    func zeroMetersIsNotANewBest() {
        #expect(!RunnerModel.isNewBestDistance(0, over: nil))
        #expect(RunnerModel.isNewBestDistance(1, over: nil))
        #expect(RunnerModel.isNewBestDistance(250, over: nil))
    }

    @Test("記録があるときは伸びたときだけ更新（同点は更新しない）")
    func updatesOnlyWhenLonger() {
        #expect(!RunnerModel.isNewBestDistance(120, over: 120))
        #expect(!RunnerModel.isNewBestDistance(119, over: 120))
        #expect(RunnerModel.isNewBestDistance(121, over: 120))
        #expect(!RunnerModel.isNewBestDistance(0, over: 0))
    }
}

/// リザルトの記録更新の印が共通の `RecordBadge` であること（#794 → #795 → #819 の統一漏れを止める・#839）。
///
/// 塗りつぶしのカプセルに戻すと、隣の「次の面へ」「もう一度」ボタンと同じ見た目になり押せるものに見える。
/// 見た目は実行では確かめられないのでソースの形で守る。
@Suite("チャリンコおじさん リザルトの記録更新の印")
struct RunnerResultBadgeScanTests {
    @Test("ステージ制・エンドレスとも、記録更新は RecordBadge で 1 回ずつ出す")
    func resultPanelsUseRecordBadge() throws {
        let source = try Self.viewSource()
        let cleared = try #require(SourceScan.declaration(of: "private var clearedDetail", in: source))
        let endless = try #require(SourceScan.declaration(of: "private var endlessDetail", in: source))

        #expect(cleared.contains(#"RecordBadge("新しい面に到達！")"#))
        #expect(endless.contains(#"RecordBadge("自己ベスト更新！")"#))
        #expect(SourceScan.matchCount(of: #"RecordBadge\("新しい面に到達！"\)"#, in: source) == 1)
        #expect(SourceScan.matchCount(of: #"RecordBadge\("自己ベスト更新！"\)"#, in: source) == 1)
    }

    @Test("リザルトの添え書きに塗りつぶしのカプセルが無い")
    func resultPanelsHaveNoFilledCapsule() throws {
        let source = try Self.viewSource()
        for header in ["private var clearedDetail", "private var endlessDetail"] {
            let body = try #require(SourceScan.declaration(of: header, in: source))
            #expect(!body.contains("Capsule()"), "\(header) に塗りつぶしのカプセルが戻っている")
        }
    }

    /// モジュール一式を読む（View をファイルへ割っても空振りしない・#831）。
    /// 説明文の言及に当たらないよう行コメントは落とす。
    private static func viewSource() throws -> String {
        SourceScan.strippingComments(try SourceScan.moduleSources("GameRunner"))
    }
}
