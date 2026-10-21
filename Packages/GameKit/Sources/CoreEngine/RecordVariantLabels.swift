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
            return variant == "endless" ? tr("とことん", language: language) : nil
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
            return variant == "singleHand" ? tr("一局戦", language: language) : nil
        case "poker":
            // `round10` は 10 回勝負（#2551）。`bonus` はチップ制の頃の区分で、記録は `PlayLog` が読み飛ばす。
            switch variant {
            case "round10": return tr("10回勝負", language: language)
            case "bonus":   return tr("ボーナスルール", language: language)
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

    private static func difficultyWord(_ raw: String, language: AppLanguage?) -> String? {
        switch raw {
        case "easy":   return tr("かんたん", language: language)
        case "normal": return tr("ふつう", language: language)
        case "hard":   return tr("むずかしい", language: language)
        default:       return nil
        }
    }
}
