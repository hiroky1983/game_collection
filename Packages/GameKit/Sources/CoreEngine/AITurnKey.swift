/// CPU 起動トリガーの識別子（対局の通し番号 × 手数）。
///
/// View は `.task(id:)` に手番の進行を表す値を渡して CPU を起動するが、手数だけを
/// 渡すと「0 手のまま後手を選んで新規対局を始めた」ときに値が変わらず、CPU の初手が
/// 起動しない（将棋 #82・五目並べ / オセロ #140）。対局の通し番号と組にすることで、
/// 手数が同じでも新規対局なら必ず `.task` が再起動される。
///
/// `gameSerial` は新規対局のたびに増やし、スナップショットには永続化しない。
public struct AITurnKey: Hashable, Sendable {
    public let gameSerial: Int
    public let ply: Int
    /// 手数が進まないまま CPU の手番が再開する局面（囲碁の「対局続行」・#1846）で進める値。
    public let epoch: Int

    public init(gameSerial: Int, ply: Int, epoch: Int = 0) {
        self.gameSerial = gameSerial
        self.ply = ply
        self.epoch = epoch
    }
}
