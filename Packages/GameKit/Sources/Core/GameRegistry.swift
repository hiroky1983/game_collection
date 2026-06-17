/// ハブが列挙する `GameModule` のレジストリ。登録順に表示される。
public struct GameRegistry {
    public let modules: [GameModule]

    public init(_ modules: [GameModule]) {
        self.modules = modules
    }

    public func module(id: String) -> GameModule? {
        modules.first { $0.id == id }
    }
}
