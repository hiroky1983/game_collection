import Foundation

/// 記録の区分名（「ふつう」「3枚めくり」など）を、区分のキーから**表示のたびに**引き直す表（#2199）。
///
/// `PlayRecord.variantLabel` は保存した時点の文字列で、言語を切り替えても書き換わらない。
/// ハブ・リザルト・共有文に出す名前は、保存済みの文字列ではなくここで引く（`RecordFormat`）。
/// こうすると、日本語で保存した記録も英語で保存した記録も、いまの表示言語で出る。
/// 保存済みデータは書き換えない（言語を切り替えるたびに保存し直しになるのを避ける）。
///
/// キーは `PlayLog.recordKey(gameID:variant:)` の形（`sudoku#normal`）。引けないキー（未知のゲーム・
/// 未知の区分）は nil を返し、呼び出し側は保存済みの `variantLabel` にフォールバックする。
///
/// 各ゲームが保存する日本語の区分名もこの表から作る（`stored`）ので、保存と表示で綴りが食い違わない。
/// ゲーム側のキーとの対応は各ゲームのテストが突き合わせる。
public enum RecordVariantLabels {
    /// 区分のキーから表示名を引く。`language` が nil ならいまの表示言語。
    public static func label(recordKey: String, language: AppLanguage? = nil) -> String? {
        let parts = recordKey.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let variant = parts[1]
        switch parts[0] {
        case "sudoku":
            switch variant {
            case "easy":   return tr("かんたん", language: language)
            case "normal": return tr("ふつう", language: language)
            case "hard":   return tr("むずかしい", language: language)
            default:       return nil
            }
        case "solitaire":
            return variant == "draw3" ? tr("3枚めくり", language: language) : nil
        case "spider":
            guard variant.hasSuffix("suit"), let count = Int(variant.dropLast(4)) else { return nil }
            return tr("%lldスート", count, language: language)
        case "minesweeper":
            return minesweeper(variant, language: language)
        case "shiritori":
            switch variant {
            case "endless":    return tr("とことん", language: language)
            case "quota-easy": return tr("かんたん", language: language)
            case "quota-hard": return tr("むずかしい", language: language)
            default:           return nil
            }
        case "concentration":
            // 神経衰弱は CPU の強さ別（#2608）。「ふつう」は区分なし。
            switch variant {
            case "cpu-weak":   return tr("CPU%@", tr("かんたん", language: language), language: language)
            case "cpu-strong": return tr("CPU%@", tr("むずかしい", language: language), language: language)
            default:           return nil
            }
        case "mahjong":
            switch variant {
            case "turtle":  return tr("亀甲", language: language)
            case "pyramid": return tr("ピラミッド", language: language)
            case "cross":   return tr("十字", language: language)
            default:        return nil
            }
        case "speed":
            return speedWord(variant, language: language)
        case "ojisanpuzzle":
            switch variant {
            case "backpain": return tr("荷運びモード", language: language)
            case "puzzle":   return tr("パズルモード", language: language)
            default:         return nil
            }
        case "anzan":
            return anzan(variant, language: language)
        case "akarikeshi":
            return difficultyWord(variant, language: language)
        case "mahjong4":
            switch variant {
            case "singleHand": return tr("一局戦", language: language)
            case "hanchan":    return tr("半荘戦", language: language)
            default:           return nil
            }
        case "poker":
            // `round10` は 10 回勝負（#2551）。`bonus` はチップ制の頃の区分で、記録は `PlayLog` が読み飛ばす。
            switch variant {
            case "round10": return tr("10回勝負", language: language)
            case "single":  return tr("単発戦", language: language)
            case "bonus":   return tr("ボーナスルール", language: language)
            default:        return nil
            }
        case "blackjack":
            // `match10` は 10 回勝負（#2552）、`single` は 1 回だけの単発戦（#2860）。
            switch variant {
            case "match10": return tr("10回勝負", language: language)
            case "single":  return tr("単発戦", language: language)
            default:        return nil
            }
        case "runner":
            return variant == "endless" ? tr("エンドレス", language: language) : nil
        case "hanafuda":
            return hanafuda(variant, language: language)
        case "shogi":
            return shogi(variant, language: language)
        case "tsunagi":
            // 線つなぎ（#2235）の盤の大きさ。数字と記号だけなので言語で変わらない。
            return ["5x5": "5×5", "7x7": "7×7"][variant]
        case "hanoi":
            // ハノイの塔（#2003）。キーは `<枚数>disks`（`HanoiModel.recordVariant`）。
            guard variant.hasSuffix("disks"), let count = Int(variant.dropLast(5)) else { return nil }
            return tr("円盤%lld枚", count, language: language)
        case "fifteen":
            // 15パズル（#2869）の盤の大きさ。4×4 は区分なし（従来の保存先）。数字と記号だけなので言語で変わらない。
            return ["3x3": "3×3", "5x5": "5×5"][variant]
        case "catpuzzle":
            // おじさんちのねこさがし（#2250）。キーは盤の大きさ（`CatPuzzleSize.rawValue`: easy / normal / hard / expert）。
            return variant == "expert" ? tr("とことん", language: language) : difficultyWord(variant, language: language)
        case "daifugo":
            // CPU の強さ別（#2604）。「ふつう」は区分なし（これまでの記録）なので、キーは入門・かんたん・むずかしいだけ。
            return cpuStrengthLabel(variant, language: language)
        case "colorrelay":
            return colorRelay(variant, language: language)
        // チェス・囲碁・五目並べ・オセロも CPU の強さ別（#2617）。「ふつう」は区分なし（これまでの記録）。
        // 走査テストが `case "<ゲームID>":` の 1 行 1 ゲームで表を読むので、まとめずに並べる。
        case "chess":
            return cpuStrengthLabel(variant, language: language)
        case "go":
            return go(variant, language: language)
        case "gomoku":
            return cpuStrengthLabel(variant, language: language)
        case "othello":
            return cpuStrengthLabel(variant, language: language)
        // ハーツ・ババ抜きも CPU の強さ別（#2716）。「ふつう」は区分なし。
        case "hearts":
            return cpuStrengthLabel(variant, language: language)
        case "oldmaid":
            return cpuStrengthLabel(variant, language: language)
        default:
            return nil
        }
    }

    /// 記録に保存する区分名（日本語）。保存済みの文字列は表示では使わない（`label` が引き直す）ので、
    /// 引けないとき・古い版が読んだときのための控えとして日本語を残す。
    public static func stored(gameID: String, variant: String) -> String {
        label(recordKey: "\(gameID)#\(variant)", language: .japanese) ?? variant
    }

    // MARK: - 組み立てる区分

    /// マインスイーパー。キーは `<行>x<列>-<地雷数>`。プリセット 3 種は名前、それ以外は盤の大きさで表す。
    private static func minesweeper(_ variant: String, language: AppLanguage?) -> String? {
        let sizes = variant.split(separator: "-").map(String.init)
        guard sizes.count == 2, let mines = Int(sizes[1]) else { return nil }
        let board = sizes[0].split(separator: "x").compactMap { Int($0) }
        guard board.count == 2 else { return nil }
        switch (board[0], board[1], mines) {
        case (9, 9, 10):    return tr("初級", language: language)
        case (16, 16, 40):  return tr("中級", language: language)
        case (20, 20, 82):  return tr("上級", language: language)
        default:            return tr("%1$lld×%2$lld・地雷%3$lld", board[0], board[1], mines, language: language)
        }
    }

    private static func speedWord(_ raw: String, language: AppLanguage?) -> String? {
        switch raw {
        case "slow":   return tr("ゆっくり", language: language)
        case "normal": return tr("ふつう", language: language)
        case "fast":   return tr("はやい", language: language)
        default:       return nil
        }
    }

    /// ぱっと暗算。キーは `d<桁>-n<個数>-<速さ>`。
    private static func anzan(_ variant: String, language: AppLanguage?) -> String? {
        let parts = variant.split(separator: "-").map(String.init)
        guard parts.count == 3, parts[0].hasPrefix("d"), parts[1].hasPrefix("n"),
              let digits = Int(parts[0].dropFirst()), let count = Int(parts[1].dropFirst()),
              let speed = speedWord(parts[2], language: language) else { return nil }
        return tr("%1$@・%2$@・%3$@", tr("%lld桁", digits, language: language),
                  tr("%lld個", count, language: language), speed, language: language)
    }

    /// 花札。キーは既定と違う軸だけを `-` でつないだもの（`r12-nosake-easy`）。
    private static func hanafuda(_ variant: String, language: AppLanguage?) -> String? {
        var labels: [String] = []
        for part in variant.split(separator: "-").map(String.init) {
            if part.hasPrefix("r"), let rounds = Int(part.dropFirst()) {
                labels.append(tr("%lld局", rounds, language: language))
            } else if part == "nosake" {
                labels.append(tr("酒の役なし", language: language))
            } else if let level = difficultyWord(part, language: language) {
                labels.append(tr("CPU%@", level, language: language))
            } else {
                return nil
            }
        }
        return labels.isEmpty ? nil : labels.joined(separator: tr("・", language: language))
    }

    /// 将棋の駒落ち。キーは `<rook|bishop>-<player|cpu>`（平手は区分を持たない）。
    private static func shogi(_ variant: String, language: AppLanguage?) -> String? {
        // 達人（#2698）の記録は `master`（平手）／`master-<手合い>`（駒落ち）。
        if variant == "master" { return tr("達人", language: language) }
        if variant.hasPrefix("master-") {
            guard let handicap = shogi(String(variant.dropFirst("master-".count)), language: language) else { return nil }
            return tr("%1$@・%2$@", tr("達人", language: language), handicap, language: language)
        }
        let parts = variant.split(separator: "-").map(String.init)
        guard parts.count == 2 else { return nil }
        let handicap: String
        switch parts[0] {
        case "rook":   handicap = tr("飛車落ち", language: language)
        case "bishop": handicap = tr("角落ち", language: language)
        default:       return nil
        }
        let dropper: String
        switch parts[1] {
        case "player": dropper = tr("自分が落とす", language: language)
        case "cpu":    dropper = tr("CPUが落とす", language: language)
        default:       return nil
        }
        return tr("%1$@・%2$@", handicap, dropper, language: language)
    }

    /// 囲碁。9路は強さのキーだけ（従来の保存先）、13路は `13`（ふつう）か `13-<強さ>`（#2868）。
    private static func go(_ variant: String, language: AppLanguage?) -> String? {
        guard variant == "13" || variant.hasPrefix("13-") else {
            return cpuStrengthLabel(variant, language: language)
        }
        let board = tr("%lld路", 13, language: language)
        guard variant != "13" else { return board }
        guard let strength = cpuStrengthLabel(String(variant.dropFirst(3)), language: language) else { return nil }
        return tr("%1$@・%2$@", board, strength, language: language)
    }

    /// CPU の強さ別の区分（`CPUStrength.recordVariantKey`）。花札と同じ「CPU◯◯」の言い方。
    private static func cpuStrengthLabel(_ variant: String, language: AppLanguage?) -> String? {
        let level: String
        switch variant {
        case "novice": level = tr("入門", language: language)
        default:
            guard let word = difficultyWord(variant, language: language) else { return nil }
            level = word
        }
        return tr("CPU%@", level, language: language)
    }

    /// いろリレー。キーは相手 3 人のとき強さだけ（`CPUStrength.recordVariantKey`）、それ以外は `cpu<人数>[-<強さ>]`（#2866）。
    private static func colorRelay(_ variant: String, language: AppLanguage?) -> String? {
        guard variant.hasPrefix("cpu") else { return cpuStrengthLabel(variant, language: language) }
        let parts = variant.dropFirst(3).split(separator: "-", maxSplits: 1).map(String.init)
        guard let first = parts.first, let count = Int(first), (1...2).contains(count) else { return nil }
        let opponents = tr("相手%lld人", count, language: language)
        guard parts.count == 2 else { return opponents }
        guard let strength = cpuStrengthLabel(parts[1], language: language) else { return nil }
        return tr("%1$@・%2$@", opponents, strength, language: language)
    }

    private static func difficultyWord(_ raw: String, language: AppLanguage?) -> String? {
        switch raw {
        case "easy":   return tr("かんたん", language: language)
        case "normal": return tr("ふつう", language: language)
        case "hard":   return tr("むずかしい", language: language)
        default:       return nil
        }
    }
}
