import SwiftUI
import Core

// MARK: - 開始前の設定

/// 局数・酒の役・CPU の強さを選ぶシート（#495）。
///
/// **ここで選んだ値は試合の開始時に焼き込まれ、途中で変えられない**（1 局 = 1 RuleSet 原則）。
/// 月見酒・花見酒はローカルルールなので、採用するかを最初に決めさせる。
public struct HanafudaSetupSheet: View {
    @Binding var draft: HanafudaOptions
    let onStart: () -> Void

    public init(draft: Binding<HanafudaOptions>, onStart: @escaping () -> Void) {
        self._draft = draft
        self.onStart = onStart
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("局数", selection: $draft.rounds) {
                        ForEach(HanafudaOptions.allowedRounds, id: \.self) { count in
                            Text("\(count)局").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("何局戦うか")
                } footer: {
                    Text("全局が終わった時点で、合計の文数が多いほうの勝ちです。")
                }

                Section {
                    Picker("CPUの強さ", selection: $draft.difficulty) {
                        ForEach(HanafudaDifficulty.allCases, id: \.self) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("CPUの強さ")
                }

                Section {
                    Toggle(isOn: $draft.sakeYakuEnabled) {
                        Label("月見酒・花見酒", systemImage: "moon.stars")
                            .foregroundStyle(Theme.ink)
                    }
                } header: {
                    Text("ローカルルール")
                } footer: {
                    Text("「芒に月＋菊に盃」「桜に幕＋菊に盃」を役として数えます。オフにすると菊に盃はタネ札としてだけ働きます。")
                }
            }
            .navigationTitle("花札こいこい")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("はじめる") { onStart() }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
        }
    }
}

// MARK: - 役の早見表

/// 対局中 1 タップで開ける役の早見表（#495 の仕様）。
///
/// 役は 12 種あり、覚えていないと「こいこいするか」を決められない。全役を 1 画面に
/// 収めて、成立条件と文数をその場で引けるようにする。
public struct HanafudaYakuSheet: View {
    let options: HanafudaOptions
    @Environment(\.dismiss) private var dismiss

    public init(options: HanafudaOptions) {
        self.options = options
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(HanafudaYaku.displayOrder, id: \.self) { yaku in
                        row(yaku)
                    }
                } header: {
                    Text("出来役")
                } footer: {
                    Text(options.sakeYakuEnabled
                         ? "この試合は月見酒・花見酒を採用しています。"
                         : "この試合は月見酒・花見酒を採用していません（灰色の行は数えません）。")
                }

                Section("倍率") {
                    labeled("7文以上", "合計が7文以上のとき2倍")
                    labeled("こいこい返し", "相手がこいこいを宣言したあとにあがると2倍")
                    labeled("両方", "重なると4倍（掛け算）")
                }
            }
            .navigationTitle("役の早見表")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func row(_ yaku: HanafudaYaku) -> some View {
        let isDisabled = !options.sakeYakuEnabled
            && (yaku == .tsukimizake || yaku == .hanamizake)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(yaku.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(isDisabled ? Theme.inkSub : Theme.ink)
                .frame(width: 76, alignment: .leading)
            Text(yaku.requirement)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Spacer(minLength: 6)
            Text("\(yaku.basePoints)文")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(isDisabled ? Theme.inkSub : Theme.coral)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(yaku.name)。\(yaku.requirement)。\(yaku.basePoints)文\(isDisabled ? "。この試合では数えません" : "")")
    }

    private func labeled(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(width: 96, alignment: .leading)
            Text(detail)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.inkSub)
        }
    }
}

// MARK: - くわしいルール

/// 遊び方ガイド（#118）から開く詳細ルール。3 行の要約に収まらない進行を説明する。
public struct HanafudaRuleSheet: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("進行", [
                "手札8枚・場札8枚で始まります。親から順に打ちます。",
                "手札を1枚出し、場の同じ月の札と合わせて取ります。合う札が無ければ場に置きます。",
                "続けて山札を1枚めくり、同じように合わせます。ここまでで1手番です。",
                "場に同じ月が3枚あるときは、4枚まとめて取れます。",
            ])
            section("こいこい", [
                "役ができたら「あがり」か「こいこい」を選びます。",
                "あがるとその場で得点が確定し、局が終わります。",
                "こいこいを選ぶと局が続き、役を伸ばせます。ただし相手にあがられると相手の得点が2倍になります。",
                "こいこいのあとは、宣言したときより文数が増えないとあがれません。",
            ])
            section("得点", [
                "合計が7文以上のとき2倍になります。",
                "相手のこいこいのあとにあがると2倍（両方重なると4倍）。",
                "だれもあがれずに手札が尽きたら流局で、その局は0文です。",
                "あがった人が次の局の親になります。流局のときは親が続きます。",
            ])
        }
    }

    private func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.coral)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("・")
                    Text(line)
                }
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.ink)
            }
        }
    }
}
