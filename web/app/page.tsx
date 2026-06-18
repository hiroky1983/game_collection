export default function Home() {
  const games = [
    { emoji: "♟️", name: "将棋", desc: "本格CPUと対局" },
    { emoji: "🔢", name: "2048", desc: "タイルを合体させて2048を目指す" },
    { emoji: "⚫", name: "五目並べ", desc: "先に5つ並べた方が勝ち" },
    { emoji: "💣", name: "マインスイーパー", desc: "地雷を避けながら全マスを開けよう" },
    { emoji: "⚪", name: "オセロ", desc: "石を挟んでひっくり返せ" },
  ];

  return (
    <div>
      <div className="text-center py-10 mb-10">
        <div className="text-6xl mb-4">🎮</div>
        <h1 className="text-4xl font-bold text-gray-900 mb-3">あそびば</h1>
        <p className="text-gray-500 text-lg">5つのゲームが楽しめるコレクションアプリ</p>
        <a
          href="https://apps.apple.com"
          className="inline-block mt-6 bg-black text-white text-sm font-semibold px-6 py-3 rounded-full hover:bg-gray-800 transition-colors"
        >
          App Storeでダウンロード
        </a>
      </div>

      <div className="grid grid-cols-1 gap-3 mb-12">
        {games.map((g) => (
          <div key={g.name} className="bg-white rounded-2xl px-5 py-4 flex items-center gap-4 shadow-sm border border-gray-100">
            <span className="text-3xl">{g.emoji}</span>
            <div>
              <p className="font-bold text-gray-900">{g.name}</p>
              <p className="text-sm text-gray-500">{g.desc}</p>
            </div>
          </div>
        ))}
      </div>

      <div className="flex justify-center gap-8 text-sm">
        <a href="/privacy" className="text-orange-500 hover:underline">プライバシーポリシー</a>
        <a href="/terms" className="text-orange-500 hover:underline">利用規約</a>
      </div>
    </div>
  );
}
