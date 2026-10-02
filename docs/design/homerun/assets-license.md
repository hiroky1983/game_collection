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

## 4. 元画像（キャラクターデザイン）: ChatGPT（OpenAI）生成

会長回答（2026-10-02・Issue #1561 コメント追記）: 「おじさんの 3D モデルの元画像は ChatGPT（OpenAI）で生成した画像
（Canva ではない）」。Meshy へ入力した元画像の出所は Canva ではなく **ChatGPT（画像生成機能）**であることが判明したため、
OpenAI の公式利用規約を一次情報で確認し追記する。

### 4.1 出典

- [OpenAI Terms of Use](https://openai.com/policies/row-terms-of-use/)（確認日 2026-10-02）

**確認方法の制約（要記録）**: 上記 URL への直接 WebFetch はいずれも Cloudflare 等のボット対策により
HTTP 403 Forbidden で取得できなかった（`openai.com` 配下は robots 保護が強く本セッションのツールからは直接本文取得不可）。
そのため本節の引用は、OpenAI 公式 URL を出典として明記した上で、複数の独立した第三者（法律系メディア等）が同一の
原文引用として一致して報告している文言を採用している。**原文の一字一句を自分でページから直接確認できたわけではない**
ため、確度は「規約の一次情報だが直接取得はできていない」扱いとし、重要な判断（配信継続の可否等）に関わる場合は
会長側のブラウザで `openai.com/policies/row-terms-of-use/` を直接開いて最終確認することを推奨する。

### 4.2 Output（生成物）の所有権

OpenAI Terms of Use（複数の第三者ソースが一致して引用する原文）:

> "As between you and OpenAI, and to the extent permitted by applicable law, you (a) retain your ownership rights in Input and (b) own the Output."

**ユーザーが Output（生成画像）を所有する**。OpenAI 側が著作権を留保する構成にはなっていない。

### 4.3 商用利用・再配布（販売・マーチャンダイズを含む）の可否

OpenAI 公式ヘルプセンター（FAQ）の記載として広く引用されている文言:

> "Subject to the Content Policy and Terms, you own the output you create with ChatGPT, including the right to reprint, sell, and merchandise – regardless of whether output was generated through a free or paid plan."

**商用利用・再配布・販売・マーチャンダイズ化が可能**で、かつ**無料プランでも有料プランでも扱いは同じ**（Meshy の
ような無料/有料の差は無い）。したがって生成に使った ChatGPT のプラン（無料/Plus 等)を厳密に特定できなくても、
この所有権・商用利用の結論には影響しない。

### 4.4 限界・留意事項

第三者分析記事で広く指摘されている留意点（規約の制約条項）:

- **出力の非唯一性**: 生成物は一意性が保証されない。他のユーザーが類似した出力を得る可能性がある
- **第三者権利侵害についての保証なし**: 出力が第三者の知的財産権を侵害しないことの保証は限定的（一部のエンタープライズ向け契約を除く）。生成に使ったプロンプト自体が実在の商標・著名キャラクター・実在人物の肖像を模倣していないことはこちらの責任で確認する必要がある
- **競合 AI 開発への転用禁止**: 生成物を OpenAI と競合する AI モデルの学習・開発に使うことは禁止

今回の用途（「Mustache Slugger」という独自名称のオリジナルキャラクターの画像生成・それを基にした 3D モデル化）は
実在の商標・著名キャラクター・実在人物を模したものではないため、上記の留意点には該当しないと判断する。

### 4.5 結論（ChatGPT 元画像について）

- **商用利用・所有権のいずれも問題なし**。ChatGPT で生成した画像をキャラクターデザインの元に使い、それを Meshy へ
  入力して 3D モデル化し、アプリに同梱・配信することは OpenAI の規約上問題ない。
- **帰属表示（クレジット）は不要**（OpenAI の規約に Meshy の無料プランのような CC BY 表示義務は無い）。
- **懸念点（要確認・勝手に対応しない）**: 本節の原文確認は `openai.com` への直接アクセスがツール側でブロックされたため、
  第三者による引用の一致をもって確認した間接的なものに留まる。法務上の厳密な裏取りが必要になった場合は、
  会長側のブラウザで一次ページを直接確認することを推奨する。また、元画像の生成に使ったプロンプトが実在の
  商標・著名キャラクター・実在人物の肖像を参照していないかは、生成した本人（会長）側の確認が必要（本書の調査範囲外）。

## 5. 参考: 関連 Issue・PR

- Issue #1561（本件・監査 2026-09-29、対象 PR: #1517・#1549・#1551・#1552・#1554・#1559）
- Issue #1348（柵越えおじさんの実装・企画倉庫）
- `Packages/GameKit/Package.swift:111-113` のコメント（打者 3D モデルの出所メモ。アプリコードのため本 PR では変更しない）

## 追記: ハブ特別枠のキービジュアル（#1761）

| アセット | 内容 | 出所 | 作成日 |
|---|---|---|---|
| `Packages/GameKit/Sources/GameHomerun/Resources/HomerunHubHeroArtLogo.jpg` | ハブ先頭の特別枠に使うロゴ入り横長画像（元 1536×1024 を 1206×804 の JPEG に縮小） | ChatGPT で生成・会長が作成。権利上の問題なしと会長が確認（#1761） | 2026-10-02 |
