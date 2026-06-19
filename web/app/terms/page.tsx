export const metadata = {
  title: "利用規約 | あそびば",
};

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mb-10">
      <h2 className="text-lg font-bold text-gray-900 dark:text-white mb-3 pb-2 border-b border-gray-200 dark:border-gray-700">{title}</h2>
      <div className="text-gray-700 dark:text-gray-300 leading-relaxed space-y-3">{children}</div>
    </section>
  );
}

export default function TermsPage() {
  return (
    <div>
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">利用規約</h1>
        <p className="text-sm text-gray-400">最終更新日：2026年6月19日</p>
      </div>

      <div className="bg-orange-50 dark:bg-orange-950 border border-orange-200 dark:border-orange-900 rounded-xl p-5 mb-10 text-sm text-orange-800 dark:text-orange-300 leading-relaxed">
        本アプリ「あそびば」をご利用いただくことで、本利用規約に同意したものとみなします。
        ご利用前に必ずお読みください。
      </div>

      <Section title="1. 本アプリについて">
        <p>
          「あそびば」は将棋・2048・五目並べ・マインスイーパー・オセロを収録したゲームコレクションアプリです。
          iOS 17.0以上のデバイスでご利用いただけます。
        </p>
      </Section>

      <Section title="2. 利用条件">
        <ul className="list-disc pl-5 space-y-1">
          <li>本アプリは個人的・非商業的な目的でのみご利用いただけます。</li>
          <li>本アプリのご利用にはApple IDが必要な場合があります。</li>
          <li>インターネット接続なしでもゲームをお楽しみいただけますが、広告の表示には接続が必要な場合があります。</li>
        </ul>
      </Section>

      <Section title="3. 禁止事項">
        <p>以下の行為を禁止します。</p>
        <ul className="list-disc pl-5 space-y-1">
          <li>本アプリのリバースエンジニアリング・逆コンパイル・改ざん・複製</li>
          <li>本アプリを用いた商業目的の利用・再配布</li>
          <li>不正な手段によるゲームデータの改変</li>
          <li>法令または公序良俗に反する行為</li>
          <li>開発者または第三者の権利を侵害する行為</li>
        </ul>
      </Section>

      <Section title="4. 知的財産権">
        <p>
          本アプリに含まれるすべてのコンテンツ（テキスト・グラフィック・サウンド・コード等）の
          著作権およびその他の知的財産権は開発者に帰属します。
          本規約によりユーザーに付与されるのは、本アプリを個人的に使用する非独占的・譲渡不可のライセンスのみです。
        </p>
      </Section>

      <Section title="5. 免責事項">
        <ul className="list-disc pl-5 space-y-1">
          <li>本アプリは現状有姿で提供されます。動作の完全性・正確性を保証するものではありません。</li>
          <li>本アプリの利用により生じた損害（データの損失・機器の故障等）について、開発者は一切の責任を負いません。</li>
          <li>本アプリは予告なく機能の追加・変更・停止・終了を行う場合があります。</li>
          <li>第三者サービス（Google AdMob等）の利用により生じた損害について、開発者は責任を負いません。</li>
        </ul>
      </Section>

      <Section title="6. アプリの更新・終了">
        <p>
          開発者は本アプリをいつでも更新・変更・終了する権利を有します。
          アプリの終了により生じた損害について、開発者は責任を負いません。
        </p>
      </Section>

      <Section title="7. 規約の変更">
        <p>
          本規約は予告なく変更される場合があります。
          変更後も引き続き本アプリをご利用いただいた場合、変更後の規約に同意したものとみなします。
          重要な変更がある場合は、アプリ内またはこのページにてお知らせします。
        </p>
      </Section>

      <Section title="8. 準拠法・管轄裁判所">
        <p>
          本規約は日本法に準拠し、日本法に従って解釈されます。
          本アプリに関する紛争については、東京地方裁判所を第一審の専属的合意管轄裁判所とします。
        </p>
      </Section>

      <Section title="9. お問い合わせ">
        <p>本規約に関するご質問・ご要望は下記にご連絡ください。</p>
        <p>
          <a href="mailto:hirockysan1983@gmail.com" className="text-orange-500 underline">
            hirockysan1983@gmail.com
          </a>
        </p>
      </Section>
    </div>
  );
}
