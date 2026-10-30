#!/usr/bin/env node
// PR 本文から「Closes #N」で閉じる対象の Issue 番号を取り出す（#3063）。
// close-issues.yml が使う。単語境界が無いと `prefixes #5` の語尾を拾って無関係な Issue を閉じる。
//
// 使い方: node Scripts/closing-issue-numbers.js < body.md   （番号を1行ずつ出力）
'use strict';

// 引用・コード・HTML コメント内の言及で誤爆しないよう、マッチ前に除去する（#109）。
// 順序は GitHub の描画と同じ「HTML コメント → フェンス → インラインコード → 引用」。
// コメントを先に消さないと、コメント内の閉じないフェンス行が後方の実フェンスと対になり、
// 間にある通常の記載まで巻き込んで消える。
// 除去部は空白ではなく NUL に置き換える。空白にすると分断されていたキーワードと番号が
// 連結して新たな誤検出になる（例: Closes `foo` #12）。
const NUL = String.fromCharCode(0);

function closingIssueNumbers(raw) {
  const body = (raw || '')
    .replace(/<!--[\s\S]*?-->/g, NUL)
    .replace(/^\s{0,3}(?:```|~~~)[\s\S]*?^\s{0,3}(?:```|~~~)\s*$/gm, NUL)
    .replace(/`[^`\n]*`/g, NUL)
    .replace(/^\s{0,3}>.*$/gm, NUL);
  const matches = [...body.matchAll(/\b(?:close[sd]?|fix(?:es|ed)?|resolve[sd]?)\s+#(\d+)/gi)];
  return [...new Set(matches.map((m) => parseInt(m[1], 10)))];
}

module.exports = { closingIssueNumbers };

if (require.main === module) {
  let input = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { input += c; });
  process.stdin.on('end', () => {
    for (const n of closingIssueNumbers(input)) console.log(n);
  });
}
