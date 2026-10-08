import Core

/// 柵越えおじさんの場面（`HomerunSound`）に対して鳴らす触覚（#1949）。
///
/// 音の発火点（`HomerunSoundPlayer`）に相乗りさせ、場面→触覚の対応をここ 1 か所に集める（`RunnerFeedbackCue` と同じ流儀）。
/// `services.feedback` は効果音（`SoundEffect`）にも相乗りして場面の音と二重に鳴るため、触覚だけの入口
/// （`GameServices.haptics`）へ渡す。設定の「触覚」オフは App 層の `GatedFeedbackService` が受け持つので、ここに条件分岐は無い。
///
/// 強さの序列: 詰まり・空振り（light）< 芯に当たった（medium）< ジャストミート・フェンス直撃（rigid）< 決着（notice）。
enum HomerunFeedbackCue: Equatable {
    case impact(FeedbackImpact)
    case notice(FeedbackNotice)

    /// 場面に対する触覚。触覚を持たない場面（打ち出し・素振り・怒り・実績・上昇音など）は nil。
    static func cue(for sound: HomerunSound) -> HomerunFeedbackCue? {
        switch sound {
        case .mitt:        return .impact(.light)       // 空振り・見送り（ミットに収まる）
        case .hitWeak:     return .impact(.light)       // 詰まった当たり（ファウル・ゴロ・たんこぶの当たり）
        case .hitGood:     return .impact(.medium)
        case .hitJust:     return .impact(.medium)      // 芯（柵越えの当たり）。結果の触覚は別に鳴る
        case .justMeet:    return .impact(.rigid)
        case .fenceHit, .backScreen:
                           return .impact(.rigid)
        case .homerun, .outOfPark:
                           return .notice(.success)
        case .foulPole:    return .notice(.warning)
        case .moonCrack:   return .notice(.success)     // 月が割れる
        case .tankobu:     return .notice(.error)       // たんこぶ
        case .machine, .swing, .moonRise, .fall, .angry, .achievement:
                           return nil
        }
    }
}

extension FeedbackService {
    /// 手応えを鳴らす。
    @MainActor func play(_ cue: HomerunFeedbackCue) {
        switch cue {
        case .impact(let style): impact(style)
        case .notice(let type):  notify(type)
        }
    }
}
