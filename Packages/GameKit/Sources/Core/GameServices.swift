/// 各ゲームに注入する横断サービス束。MVP では永続化と広告のみ。
public struct GameServices {
    public let snapshots: SnapshotStore
    public let ads: AdService

    public init(snapshots: SnapshotStore, ads: AdService) {
        self.snapshots = snapshots
        self.ads = ads
    }
}
