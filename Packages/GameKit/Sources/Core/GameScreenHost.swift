import SwiftUI

/// ゲーム画面を**一度だけ**作って持ち続ける入れ物（#1926）。
///
/// ハブの `navigationDestination` はハブが描き直されるたびに評価し直され、そのたびに
/// `module.makeView(services:)` が走る。各ゲームの View は init で model を作るので、
/// SwiftUI が使わない（最初の 1 つ以外の）model が毎回生まれて捨てられる。model の init に
/// 副作用（解析 `game_start`・探索・保存）があるゲームでは、その副作用も捨てられる model の分だけ走る。
///
/// ここで 1 回しか作らないようにすると、ゲーム側は init の作り方を変えずに済み、新しいゲームも
/// 同じ経路を通る限り自動で守られる。**ゲーム画面を作る場所は `HubView` の 1 か所だけ**にし、
/// 必ずこの入れ物を通すこと（`RecordShareWiringTests` が走査して固定する）。
public struct GameScreenHost: View {
    @State private var holder: GameScreenHolder

    public init(_ make: @escaping @MainActor () -> AnyView) {
        // `State(initialValue:)` の値は親の評価のたびに作られて捨てられうるので、ここでは
        // 何も作らない入れ物（`GameScreenHolder`）だけを渡す。ゲーム画面は最初の body で作る。
        _holder = State(initialValue: GameScreenHolder(make))
    }

    public var body: some View {
        holder.screen
    }
}

/// `make` を最初に読まれたときに 1 回だけ呼び、以降は同じ値を返す。
@MainActor
final class GameScreenHolder {
    private var make: (@MainActor () -> AnyView)?
    private var built: AnyView?

    init(_ make: @escaping @MainActor () -> AnyView) {
        self.make = make
    }

    var screen: AnyView {
        if let built { return built }
        let view = make?() ?? AnyView(EmptyView())
        built = view
        make = nil
        return view
    }
}
