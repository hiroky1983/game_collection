import Foundation
import os

/// 中断データの保存に失敗したときの記録先（#3382）。
///
/// 以前は各ゲームが `try? services?.snapshots.save(...)` で失敗を握りつぶしていたため、空き容量不足などで
/// 「続きから」が古い盤に戻っても原因が残らなかった。**画面にも解析にも出さず**、ログにだけ残す。
public enum SnapshotSaveFailure {
    private static let logger = Logger(subsystem: "jp.asobiba.GameCollection", category: "SnapshotStore")

    /// 既定の報告。本番は `os.Logger` に gameID とエラーを出し、DEBUG ではさらに `assertionFailure` で気づけるようにする。
    public static func log(gameID: String, error: Error) {
        logger.error("中断データの保存に失敗 gameID=\(gameID, privacy: .public) error=\(String(describing: error), privacy: .public)")
        #if DEBUG
        assertionFailure("中断データの保存に失敗: \(gameID) \(error)")
        #endif
    }
}

public extension SnapshotStore {
    /// 失敗を握りつぶさず報告する保存口。ゲームの保存は `try?` ではなくこちらを使う（#3382）。
    ///
    /// 保存の挙動（形式・保存先・書き込み方）は `save` のまま変えない。失敗時に `report` を呼ぶだけ。
    /// `report` はテストで差し替える口で、既定は `SnapshotSaveFailure.log`。
    /// - Returns: 保存に成功したか。
    @discardableResult
    func saveReportingFailure<T: Codable>(
        _ snapshot: T,
        for gameID: String,
        report: (_ gameID: String, _ error: Error) -> Void = SnapshotSaveFailure.log
    ) -> Bool {
        do {
            try save(snapshot, for: gameID)
            return true
        } catch {
            report(gameID, error)
            return false
        }
    }
}
