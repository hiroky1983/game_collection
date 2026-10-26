import Testing
import Core
@testable import GameRunner

/// ミスの原因の 1 行（#1755）。すべての原因に空でない文が付く。
@Suite("RunnerView.missCauseText")
struct MissCauseTextTests {
    @Test("全ての原因に別々の文が付く")
    func everyCauseHasDistinctText() {
        let texts = AnalyticsEndCause.allCases.map { RunnerView.missCauseText($0) }
        #expect(texts.allSatisfy { !$0.isEmpty })
        #expect(Set(texts).count == texts.count)
        #expect(RunnerView.missCauseText(.pit) == "穴に落ちた")
        #expect(RunnerView.missCauseText(.rock) == "岩にぶつかった")
    }
}

/// 当たった相手 → ミスの 1 行（#2254）。港町の車（フォークリフト）が「動物」と出た不具合の再発防止。
@Suite("RunnerView.missText（当たった相手と文言の対応・#2254）")
struct MissTextTests {
    private func text(_ kind: RunnerHazardKind, _ world: RunnerWorld) -> String {
        RunnerView.missText(cause: kind.missCause, object: .hazard(kind), world: world)
    }

    @Test("港町: イノシシの枠はフォークリフト、犬の枠は猫（動物とは言わない）")
    func harborBoarSlotIsForklift() {
        #expect(text(.boar, .harbor) == "フォークリフトにぶつかった")
        #expect(text(.dog, .harbor) == "猫にぶつかった")
        #expect(text(.boar, .harbor) != RunnerView.missCauseText(.animal))
    }

    @Test("当たった相手ごとの文言（世界ごとの着せ替えに合わせる）")
    func objectToText() {
        let table: [(RunnerHazardKind, RunnerWorld, String)] = [
            (.dog, .morning, "犬にぶつかった"),
            (.boar, .morning, "イノシシにぶつかった"),
            (.dog, .kyotoNara, "鹿にぶつかった"),
            (.dog, .onsen, "サルにぶつかった"),
            (.boar, .satoyama, "イノシシにぶつかった"),
            (.lowBlock, .morning, "岩にぶつかった"),
            (.lowBlock, .satoyama, "切り株にぶつかった"),
            (.lowBlock, .harbor, "ロープにぶつかった"),
            (.tallBlock, .harbor, "ドラム缶にぶつかった"),
            (.lowBlock, .onsen, "湯桶にぶつかった"),
            (.tallBlock, .onsen, "岩にぶつかった"),
            (.shoot, .satoyama, "竹の子にぶつかった"),
            (.shoot, .harbor, "波しぶきにぶつかった"),
            (.geyser, .onsen, "湯柱にぶつかった"),
            (.wall, .satoyama, "石垣にぶつかった"),
            (.wall, .harbor, "コンテナにぶつかった"),
            (.bird, .harbor, "鳥にぶつかった。跳ばずに走って下を抜けよう"),
        ]
        for (kind, world, expected) in table {
            #expect(text(kind, world) == expected, "\(kind)・\(world)")
        }
    }

    @Test("台座の正面は台座の見た目で言う")
    func platformFace() {
        func face(_ world: RunnerWorld) -> String {
            RunnerView.missText(cause: .rock, object: .platformFace, world: world)
        }
        #expect(face(.morning) == "足場にぶつかった")
        #expect(face(.satoyama) == "わら積みにぶつかった")
        #expect(face(.harbor) == "木箱にぶつかった")
    }

    @Test("崩れる足場の正面は足場の見た目（吊り橋・桟橋）で言う（#2285）")
    func crumblingPlatformFace() {
        func face(_ world: RunnerWorld) -> String {
            RunnerView.missText(cause: .rock, object: .crumblingPlatformFace, world: world)
        }
        #expect(face(.satoyama) == "吊り橋にぶつかった")
        #expect(face(.harbor) == "桟橋にぶつかった")
        #expect(face(.kyotoNara) == "吊り橋にぶつかった")
        for world in RunnerWorld.allCases {
            #expect(face(world) != RunnerView.missText(cause: .rock, object: .platformFace, world: world))
        }
    }

    @Test("相手が無い原因（穴・沈む床）は従来の文のまま")
    func causeOnly() {
        #expect(RunnerView.missText(cause: .pit, object: nil, world: .harbor) == "穴に落ちた")
        #expect(RunnerView.missText(cause: .sink, object: nil, world: .harbor) == "沈んでしまった")
    }

    @Test("全ての世界・全ての障害に文があり、英語がある")
    func everyCombinationHasTextAndEnglish() {
        let kinds: [RunnerHazardKind] = [.lowBlock, .tallBlock, .bird, .dog, .boar, .shoot, .geyser, .wall]
        for world in RunnerWorld.allCases {
            var texts = kinds.map { text($0, world) }
            texts.append(RunnerView.missText(cause: .rock, object: .platformFace, world: world))
            texts.append(RunnerView.missText(cause: .rock, object: .crumblingPlatformFace, world: world))
            for t in texts {
                #expect(!t.isEmpty)
                #expect(GameRunner.tr.hasTranslation(t, language: .english), "「\(t)」に英語が無い（\(world)）")
            }
        }
    }

    @Test("全ステージを跳ばずに走ると、当たった相手が死因と矛盾せず記録される")
    func fieldRecordsObjectConsistentWithCause() {
        var hit = 0
        for stage in RunnerStage.all {
            var field = RunnerField(stage: stage)
            #expect(field.lastMissObject == nil)
            var events: [RunnerEvent] = []
            var frames = 0
            while !events.contains(where: { $0.isTerminal }), frames < 60 * 120 {
                frames += 1
                events += field.step(dt: 1.0 / 60)
            }
            guard events.contains(.crashed) else {
                #expect(field.lastMissObject == nil, "ステージ \(stage.number): 穴・沈みに相手は無い")
                continue
            }
            hit += 1
            switch field.lastMissObject {
            case .hazard(let kind)?:
                #expect(kind.missCause == field.lastMissCause, "ステージ \(stage.number): \(kind)")
            case .platformFace?, .crumblingPlatformFace?:
                #expect(field.lastMissCause == .rock, "ステージ \(stage.number)")
            case nil:
                Issue.record("ステージ \(stage.number): ぶつかったのに相手が記録されていない")
            }
        }
        #expect(hit > 0)
    }
}
