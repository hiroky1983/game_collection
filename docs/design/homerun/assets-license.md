# 柵越えおじさん 3D アセット（Meshy 製 USDZ）の出所とライセンス

Issue #1561（監査 2026-09-29・会長回答 2026-10-02）への対応。`Packages/GameKit/Sources/GameHomerun/Resources/HomerunBatter.usdz`
の出所・生成プラン・利用規約の確認結果をここに記録する。**この文書はライセンス条件の記録のみ**で、
アプリコード（`Packages/GameKit/Package.swift` 等）は変更しない。

## 1. 対象アセットと生成プラン

| アセット | 内容 | 生成時期（目安） | 追加されたコミット | 生成プラン |
|---|---|---|---|---|
| `HomerunBatter.usdz` の本体モデル・右打ちスイング | Meshy の text-to-3D で生成した打者モデル「Mustache Slugger」+ Meshy text-to-motion によるスイングの動き | 2026-09-28 頃 | `b56a79a4` ほか「打者を Meshy の 3D おじさんに差し替える」（`prototype/homerun` 系ブランチ） | **Pro**（会長回答 2026-10-02） |
| 空振り後の動き（倒れて目を回す演出） | 同モデルに Meshy text-to-motion で追加したアニメーション | 2026-10-01〜02 頃 | `d206934f`「空振りで回って倒れて目を回す演出（#1681）」（`feat/1681-homerun-whiff-gag`） | **Pro**（会長回答 2026-10-02。両生成とも同一プランとして回答を得た） |

会長回答（2026-10-02・Issue #1561 コメント）: 「Meshy のプランは Pro（安い方の月額プラン）」。本書はこの回答を前提に
Pro プランの利用規約を確認した内容であり、Meshy 社の課金ログ等の一次証跡は未取得（取得が必要になった場合は会長の
Meshy アカウントでの確認が必要）。

## 2. Meshy 利用規約の確認結果（一次情報）

確認日: **2026-10-02**。出典は Meshy 公式サイト・公式ヘルプセンターの一次情報のみ（第三者のまとめサイトは参考に留め、
本書の結論の根拠にはしていない）。

### 2.1 出典

- [Meshy Terms of Use](https://www.meshy.ai/terms-of-use)（確認日 2026-10-02）
- [Meshy Pricing](https://www.meshy.ai/pricing)（確認日 2026-10-02）
- [Meshy Pricing & Credits（公式ドキュメント）](https://docs.meshy.ai/en/webapp/pricing)（確認日 2026-10-02）
- [Can I use my generated assets for commercial projects?（公式ヘルプ）](https://help.meshy.ai/en/articles/9992001-can-i-use-my-generated-assets-for-commercial-projects)（確認日 2026-10-02）
- [Can I use Meshy assets commercially?（公式ヘルプ）](https://help.meshy.ai/en/articles/16102098-can-i-use-meshy-assets-commercially)（確認日 2026-10-02）
- [What is included on the Free plan?（公式ヘルプ）](https://help.meshy.ai/en/articles/15696428-what-is-included-on-the-free-plan)（確認日 2026-10-02）

### 2.2 商用利用の可否

**可能**。無料プラン・有料プラン（Pro 含む）とも商用利用自体は許可されている。ただし帰属表示の要否がプランで異なる（2.4 参照）。

### 2.3 所有権／ライセンスの帰属

Meshy Terms of Use 原文（有料プラン利用者に関する条項）:

> "As between Meshy and those Customers on a paid Meshy plan ... such customers own their Customer Output."

**Pro プラン（有料プラン）で生成したアセットはユーザー（当方）が所有する**。Meshy 側は「非独占的・ロイヤリティフリーの
世界的ライセンス」を保持するのみで、著作権自体はこちらに帰属する。前提条件は「生成に使った素材（アップロードした参照画像等）が
第三者の著作権を侵害していないこと」。今回の生成は text-to-3D／text-to-motion（テキストプロンプトからの生成）であり、
著作権のある画像を参照素材としてアップロードした記録は確認できていない（未確認。実際に参照画像を使っていた場合は要再確認）。

無料プランの場合は対照的に、Meshy が著作権を保持し、ユーザーには CC BY 4.0（クレジット表記必須）でライセンスされる。
**今回は Pro のためこの無料プラン条件は適用されない。**

### 2.4 クレジット表記の要否

**Pro プランでは不要**。クレジット表記（帰属表示）が必須なのは無料プランの CC BY 4.0 ライセンスのみで、Pro 以上の
有料プランは「private license」として帰属表示なしでの商用利用・配布・販売が認められる。

→ 受け入れ条件「帰属表示が必要な場合、その実装方針」については、**Pro プランのため帰属表示自体が不要であり、
アプリ内クレジット表示の追加実装は不要**と判断する。

### 2.5 アプリへの同梱・配信の可否

**可能**。Meshy Pricing ページおよびヘルプ記事では、Pro（有料）プランで生成したモデルについて
「the models you create using Meshy are exclusively yours, and you have full rights to distribute and sell them」
（デジタル販売・ゲームやアプリへの組み込み・物理商品化を含む）と明記されている。ゲームアプリのバイナリに USDZ を
同梱して配信することは、この「distribute」の範囲に含まれる。

### 2.6 解約後も使い続けられるか

**使い続けられる**。Meshy 公式ヘルプ記事によれば、生成物に紐づく権利は「生成した時点のプランのステータス」に基づいて
決まり、有料プランで生成したモデルはその後ユーザーが無料プランへダウングレード（解約）しても、有料プラン時点の
private license（所有権）が維持される。したがって Meshy の Pro 契約を将来解約しても、Pro 契約中に生成した
`HomerunBatter.usdz` の利用（配信継続）には影響しない。

### 2.7 生成物の公開範囲（Pro で非公開か）

**Pro プランは非公開（private）が既定**。無料プランの生成物は CC BY 4.0 の下で（コミュニティ上など）公開される前提だが、
Pro プランは「private assets」として扱われ、第三者に公開されない。公開範囲の設定自体を手動で変更した記録は無いが、
規約上 Pro の既定が non-public である点は確認できた。

### 2.8 禁止事項

Meshy Terms of Use で確認できた主な禁止事項:

- 第三者の著作権・商標権を侵害する素材（参照画像等）を使って生成すること
- 生成した 3D アセットを使って、Meshy と競合する AI モデルを学習・開発・改善すること
  （原文: "use generated digital assets to train, develop, or improve AI models that are competitive with Meshy"）
- 欺瞞・詐欺的な用途、個人を特定できる情報を含む生成物の作成
- 著作権者の許諾のない実在の商標・キャラクター等を模した生成（打者モデルは「Mustache Slugger」という独自名称のキャラクターで、
  実在の商標・著名キャラクターを模したものではない）

今回の用途（アプリ内キャラクターとしての表示・配信）はいずれにも該当しない。

## 3. 結論・規約上の懸念点

- **商用利用・同梱配信・所有権・解約後の継続利用のいずれも問題なし**（Pro プランの規約上、明確に許可されている）。
- **クレジット表記は不要**（Pro プランのため）。Issue #1561 の受け入れ条件「帰属表示が必要な場合の実装方針」は
  「Pro プランのため帰属表示自体が不要」で完結し、追加のアプリ内クレジット表示実装は不要と判断する。
- **未確認点（要フォローが必要な場合は会長判断）**: 生成時に著作権のある参照画像（実在人物の写真など）をアップロードした
  かどうかは本書の調査だけでは確認できていない。テキストプロンプトのみでの生成であれば規約上の懸念は無いが、
  もし何らかの参照画像を使っていた場合はその画像自体の権利関係を別途確認する必要がある。
- Meshy の具体的な契約開始日・支払い記録（一次証跡）は未確認（本書は会長回答「Pro」を前提にした規約確認のみ）。

## 4. 参考: 関連 Issue・PR

- Issue #1561（本件・監査 2026-09-29、対象 PR: #1517・#1549・#1551・#1552・#1554・#1559）
- Issue #1348（柵越えおじさんの実装・企画倉庫）
- `Packages/GameKit/Package.swift:111-113` のコメント（打者 3D モデルの出所メモ。アプリコードのため本 PR では変更しない）
