export const metadata = {
  title: "プライバシーポリシー | あそびば",
};

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mb-10">
      <h2 className="text-lg font-bold text-gray-900 dark:text-white mb-3 pb-2 border-b border-gray-200 dark:border-gray-700">{title}</h2>
      <div className="text-gray-700 dark:text-gray-300 leading-relaxed space-y-3">{children}</div>
    </section>
  );
}

export default function PrivacyPage() {
  return (
    <div>
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">プライバシーポリシー</h1>
        <p className="text-sm text-gray-400">最終更新日：2026年9月23日</p>
      </div>

      <div className="bg-orange-50 dark:bg-orange-950 border border-orange-200 dark:border-orange-900 rounded-xl p-5 mb-10 text-sm text-orange-800 dark:text-orange-300 leading-relaxed">
        本アプリ「あそびば」をご利用いただくにあたり、ユーザーの皆様のプライバシーを大切にしています。
        本ポリシーでは、情報の収集・利用方法についてご説明します。
      </div>

      <Section title="1. 収集する情報">
        <p>本アプリは以下の情報を収集する場合があります。</p>
        <ul className="list-disc pl-5 space-y-1">
          <li>広告配信のための端末識別情報（広告ID）</li>
          <li>アプリの利用状況に関する匿名の統計情報（プレイしたゲーム・プレイ時間・成績などで、個人を特定する情報は含みません）</li>
          <li>クラッシュ・不具合の発生時に、アプリの安定性向上のための診断情報（端末の機種・OSバージョン・発生箇所など）</li>
          <li>広告表示の最適化のため、Google の広告・解析SDKがおおよその位置情報（市区町村程度の粒度）を利用する場合があります</li>
          <li>Game Center にサインインしている場合、スコア・ランキング・実績（Apple のGame Centerサービスを通じて送信・表示されます）</li>
        </ul>
        <p className="mt-2">
          氏名・住所・メールアドレスなど、個人を直接特定できる情報は一切収集しません。
        </p>
      </Section>

      <Section title="2. ゲームデータの保存">
        <p>
          各ゲームの進行状況・設定はお使いのデバイス内にのみ保存されます。
        </p>
        <p>
          ベストスコアなどの記録は、Game Center にサインインしている場合に限り Apple のサーバーへ送信されます（サインインしていない場合は端末内のみに保存されます）。
        </p>
        <p>
          「続きのお知らせ」「久しぶり通知」などのお知らせは、端末内で処理するローカル通知です。これらの通知のために外部サーバーへ情報を送信することはありません。
        </p>
        <p>
          基本的にインターネット接続なしでもご利用いただけますが、広告の表示・統計情報の送信・Game Centerとの連携には接続が必要です。
        </p>
      </Section>

      <Section title="3. 使用している外部サービス">
        <p>本アプリは以下の外部サービスを利用しています。</p>
        <ul className="list-disc pl-5 space-y-2">
          <li>
            <span className="font-semibold">Google AdMob</span>（広告配信）：より関連性の高い広告を表示するために、広告IDなどの情報を利用する場合があります。
          </li>
          <li>
            <span className="font-semibold">Firebase Analytics</span>（Google）：アプリの利用状況を、上記1に記載の匿名の統計情報として収集します。
          </li>
          <li>
            <span className="font-semibold">Firebase Crashlytics</span>（Google）：クラッシュ発生時に、アプリの安定性向上のための診断情報を自動的に送信します。設定の「利用状況の送信」をオフにした場合も、この診断情報の送信は継続します。
          </li>
          <li>
            <span className="font-semibold">Apple Game Center</span>：サインインしている場合、スコア・実績の送信および表示に利用します。Apple のアカウントに基づくため、本アプリが別途これらの情報を保持することはありません。
          </li>
        </ul>
        <p>
          iOSでは、App Tracking Transparency（ATT）に基づきトラッキングの許可をお伺いする場合があります。
          許可しない場合でもすべての機能を制限なくご利用いただけます。
        </p>
        <p>
          Googleのプライバシーポリシーは
          <a
            href="https://policies.google.com/privacy"
            className="text-orange-500 underline"
            target="_blank"
            rel="noopener noreferrer"
          >
            こちら
          </a>
          、Appleのプライバシーポリシーは
          <a
            href="https://www.apple.com/legal/privacy/"
            className="text-orange-500 underline"
            target="_blank"
            rel="noopener noreferrer"
          >
            こちら
          </a>
          をご確認ください。
        </p>
      </Section>

      <Section title="4. 第三者への情報提供">
        <p>
          以下の場合を除き、収集した情報を第三者に販売・貸与・提供することはありません。
        </p>
        <ul className="list-disc pl-5 space-y-1">
          <li>法令に基づき開示が必要な場合</li>
          <li>広告配信のためにGoogle AdMobと共有する場合（上記3の範囲内）</li>
          <li>利用状況の解析・アプリの安定性向上のためにGoogle（Firebase Analytics・Crashlytics）と共有する場合（上記3の範囲内）</li>
          <li>スコア・実績の記録・表示のためにApple（Game Center）と共有する場合（サインインしている場合のみ）</li>
        </ul>
      </Section>

      <Section title="5. お子様のプライバシー">
        <p>
          本アプリは13歳未満のお子様から意図的に個人情報を収集することはありません。
          お子様が個人情報を提供したことが判明した場合は、速やかに削除いたします。
        </p>
      </Section>

      <Section title="6. セキュリティ">
        <p>
          個人情報の適切な管理に努めますが、インターネット上の送信方法や電子的な保存方法が
          100%安全であることを保証するものではありません。
        </p>
      </Section>

      <Section title="7. ポリシーの変更">
        <p>
          本ポリシーは必要に応じて変更される場合があります。
          変更後のポリシーは本ページに掲載した時点で効力を生じます。
        </p>
      </Section>

      <Section title="8. お問い合わせ">
        <p>本ポリシーに関するご質問・ご要望は下記にご連絡ください。</p>
        <p>
          <a href="mailto:hirockysan1983@gmail.com" className="text-orange-500 underline">
            hirockysan1983@gmail.com
          </a>
        </p>
      </Section>
    </div>
  );
}
