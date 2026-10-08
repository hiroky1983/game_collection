import SwiftUI
import Testing
import Core
import CoreTestSupport

/// 再発防止（#1912）。全モジュールの画面を開いただけ（1 手も遊んでいない）の状態で、中断データが
/// 保存されるゲームは `hasResumableSnapshot` が false でなければならない。#1847 の 3 本・#1912 の 4 本と、
/// 同じ取りこぼしを新しいゲームが繰り返すのをここで止める。
@Suite("手つかずの盤は続きから扱いにしない（全モジュール走査・#1912）")
@MainActor
struct UntouchedSnapshotScanTests {
    /// 画面を開いただけで保存されるゲームの本数の下限（走査が空振りしていないことの担保。2026-10 時点で 5 本）。
    /// 増える分には通る。減ったら画面の組み立てが変わっていないか疑う。ナンプレ・花札のように
    /// 開始操作（難易度・設定シート）のあとに保存するゲームはここに数えず、個別の `*ResumableSnapshotTests` が見る。
    private static let minimumSavingGames = 5

    /// 例外（開いただけで保存され、かつ続きとして扱ってよいゲーム）。理由を付けて列挙する。
    private static let exceptions: [String: String] = [:]

    @Test("開いただけで保存されるゲームは、手つかずなら続きと判定しない")
    func untouchedSnapshotsAreNotResumable() {
        var saved: [String] = []
        var offenders: [String] = []
        for module in makeHubModules() where Self.exceptions[module.id] == nil {
            let store = MemorySnapshotStore()
            _ = module.makeView(services: GameServices(snapshots: store, ads: NoopAdService()))
            guard store.exists(for: module.id) else { continue }
            saved.append(module.id)
            if module.hasResumableSnapshot(in: store) { offenders.append(module.id) }
        }
        #expect(offenders.isEmpty, "手つかずなのに続きと判定される: \(offenders)（保存したゲーム: \(saved)）")
        #expect(saved.count >= Self.minimumSavingGames, "走査が空振りしている: 保存したのは \(saved)")
    }
}
