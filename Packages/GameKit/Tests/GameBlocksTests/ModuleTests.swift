import Core
import Testing
@testable import GameBlocks

@Suite("ブロック崩しのモジュール登録")
struct ModuleTests {

    /// `BlocksModule.id` は LP 照合スクリプトの都合で**文字列リテラル**で書いてあり、
    /// `BlocksModel.gameID` とは別々に書かれている。食い違うと
    /// 「記録・解析・中断データが別のキーに書かれる」という静かな故障になるので、ここで縛る。
    @Test("モジュールの id と Model の gameID が一致する")
    func idsMatch() {
        #expect(BlocksModule().id == BlocksModel.gameID)
        #expect(BlocksModule().id == "blocks")
    }

    /// 元祖アーケード作品の商標（Atari の `Breakout`）は、表示に出る文言だけでなく
    /// **ID と URL スラッグにも入れない**（#463 の権利チェック・`docs/aso/metadata-v1.1.1.md` §3）。
    @Test("表示名・説明・ID に使用禁止語が入っていない")
    func avoidsTrademarkedTerms() {
        let module = BlocksModule()
        let surfaces = [module.id, module.title, module.description]
        for forbidden in ["breakout", "ブレイクアウト", "arkanoid", "アルカノイド"] {
            for surface in surfaces {
                #expect(
                    !surface.lowercased().contains(forbidden.lowercased()),
                    "使用禁止語 '\(forbidden)' が '\(surface)' に入っている"
                )
            }
        }
        #expect(module.title == "ブロック崩し", "表示名はジャンルの一般名称")
    }

    @Test("遊び方ガイドがこのゲームの ID に紐づいている")
    func howToPlayGuideIsWired() {
        #expect(HowToPlayGuide.blocks.gameID == BlocksModel.gameID)
        #expect(HowToPlayGuide.all.contains { $0.gameID == BlocksModel.gameID })
    }
}
