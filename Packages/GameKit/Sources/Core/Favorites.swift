import Foundation
import Observation
import SwiftUI
import CoreEngine

/// お気に入りのゲーム（#3478）。ハブの☆とゲーム画面のヘッダーの☆が**同じ 1 つの置き場**を読み書きする。
///
/// 保存するのは「お気に入りにしたゲームの ID を追加した順に並べた配列」だけ（端末内の `UserDefaults` の 1 キー・サーバ不要）。
/// 件数の上限は登録ゲーム数（`registeredIDs` に無い ID・重複は読み込み時に捨てる）。
/// 並べ替え・非表示の設定（`GameSettings`）とは独立で、互いの状態に触れない。
@MainActor
@Observable
public final class FavoritesStore {
    public static let storageKey = "favoriteGames_v1"

    /// お気に入りに追加した順（古い順）。
    public private(set) var ids: [String]
    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameter registeredIDs: 今登録されているゲームの ID。渡すと、無くなったゲームの ID は読み込み時に捨てる。
    public init(defaults: UserDefaults = .standard, registeredIDs: [String]? = nil) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.storageKey) ?? []
        var seen = Set<String>()
        let registered = registeredIDs.map(Set.init)
        self.ids = stored.filter { id in
            guard registered?.contains(id) ?? true else { return false }
            return seen.insert(id).inserted
        }
    }

    public func isFavorite(_ id: String) -> Bool { ids.contains(id) }

    /// 付け外しして、**操作の後に**お気に入りかどうかを返す。
    @discardableResult
    public func toggle(_ id: String) -> Bool {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
            save()
            return false
        }
        ids.append(id)
        save()
        return true
    }

    /// 「元に戻す」用。外したゲームを**元の位置**へ戻す（追加順を保つ）。すでにお気に入りなら何もしない。
    public func restore(_ id: String, at index: Int) {
        guard !ids.contains(id) else { return }
        ids.insert(id, at: min(max(0, index), ids.count))
        save()
    }

    public func index(of id: String) -> Int? { ids.firstIndex(of: id) }

    private func save() {
        defaults.set(ids, forKey: Self.storageKey)
    }
}

/// ゲーム画面のヘッダーの☆に渡す、いま開いているゲームのお気に入り（#3478）。ハブがゲーム画面を作るところで環境に載せる。
///
/// ゲームのモジュールは自分の ID も置き場も知らなくてよい（共通枠 `gameChrome` が環境から読んで☆を出す）。
/// 環境に無いとき（ハブ以外から開いたプレビュー・テスト）は☆を出さない。
public struct FavoriteGameContext {
    public let gameID: String
    public let title: String
    let store: FavoritesStore
    let record: (FavoriteState, FavoriteSource) -> Void

    @MainActor
    public init(gameID: String, title: String, store: FavoritesStore,
                record: @escaping (FavoriteState, FavoriteSource) -> Void) {
        self.gameID = gameID
        self.title = title
        self.store = store
        self.record = record
    }

    /// 読んだ View の `body` が置き場を監視する（`FavoritesStore` が `@Observable` のため）。
    @MainActor public var isOn: Bool { store.isFavorite(gameID) }

    /// 付け外しして、解析（`favorite_toggle`）を送り、VoiceOver へ知らせ、出すトーストを返す。
    @MainActor
    func toggle(source: FavoriteSource) -> FavoriteHeaderToast {
        let isOn = store.toggle(gameID)
        record(isOn ? .on : .off, source)
        let message = isOn ? tr("お気に入りに追加しました") : tr("お気に入りから外しました")
        AccessibilityNotification.Announcement(message).post()
        return FavoriteHeaderToast(message: message)
    }

    /// ヘッダーのボタン・「…」の項目に出す名前（押すとどうなるか）。
    @MainActor public var actionTitle: String { isOn ? tr("お気に入りから外す") : tr("お気に入りに追加") }
}

private struct FavoriteGameContextKey: EnvironmentKey {
    nonisolated(unsafe) static var defaultValue: FavoriteGameContext? = nil
}

public extension EnvironmentValues {
    /// いま開いているゲームのお気に入り（#3478）。無いときはヘッダーに☆を出さない。
    var favoriteGame: FavoriteGameContext? {
        get { self[FavoriteGameContextKey.self] }
        set { self[FavoriteGameContextKey.self] = newValue }
    }
}

// MARK: - ☆

/// お気に入りの☆（#3478）。タイル・ヘッダー・メニューで同じ見た目にそろえる。
///
/// 登録済み＝黄色の塗り（`Theme.yellow`）＋枠線 #976400（`Theme.Hex.yellowText` のライト値で固定。ダーク値は黄色そのもので枠が消えるため）。
/// 未登録＝塗りなし・枠線だけ `Theme.inkSubText`。`star.fill` の上に `star` を重ねる 2 枚重ね。
public struct FavoriteStar: View {
    public let isOn: Bool
    public var size: CGFloat

    public init(isOn: Bool, size: CGFloat = 20) {
        self.isOn = isOn
        self.size = size
    }

    /// 登録済みの枠線の色（ダークでも固定）。
    static let outlineOn = Color(hex: Theme.Hex.yellowText.light)

    public var body: some View {
        ZStack {
            if isOn {
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.yellow) // accent-text-ok: 星の塗り（面）。枠線は別に重ねる
            }
            Image(systemName: "star")
                .foregroundStyle(isOn ? Self.outlineOn : Theme.inkSubText)
        }
        .scaledFont(size, weight: .semibold, maxScale: 1.3)
        .accessibilityHidden(true)
    }
}

// MARK: - ヘッダーのトースト

/// ゲーム中、ヘッダーのすぐ下に 2 秒だけ出す案内（#3478）。回ごとの ID で消える時間を数える（続けて押しても数え直す）。
struct FavoriteHeaderToast: Equatable {
    let message: String
    let id = UUID()
}

/// ヘッダーの下に `toast` を 2 秒出す。押しても邪魔にならないよう、タッチは通す。
struct FavoriteToastOverlay: ViewModifier {
    @Binding var toast: FavoriteHeaderToast?
    /// ヘッダーの高さ（全画面の枠は自前のヘッダーがコンテンツの外にあるので 0）。
    var topInset: CGFloat = 0
    @Environment(\.favoriteGame) private var favorite

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    ToastNotice(message: toast.message, onDismiss: { self.toast = nil })
                        .allowsHitTesting(false)
                        .padding(.top, topInset)
                        .transition(.opacity)
                }
            }
            .gameAnimation(.easeOut(duration: 0.2), value: toast)
            #if DEBUG
            // 撮影・動作確認用（DEBUG 限定）: `-simulateFavoriteHeaderTap` で、開いた直後にヘッダーの☆を押したのと同じ経路を通す。
            // シミュレータはタップを自動化できないため。
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-simulateFavoriteHeaderTap"), let favorite else { return }
                try? await Task.sleep(for: .milliseconds(1500))
                toast = favorite.toggle(source: .header)
            }
            #endif
            .task(id: toast) {
                guard toast != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                toast = nil
            }
    }
}
