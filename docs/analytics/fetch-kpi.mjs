#!/usr/bin/env node
// KPI の自動取得（#781）。ASC 売上・App Analytics / GA4 / AdMob を読み取り専用で叩いて表にする。
//
//   export PATH="$HOME/.nodenv/shims:$PATH"   # システム既定の node v14 では fetch が無い（Node 18 以上が要る）
//   node docs/analytics/fetch-kpi.mjs asc-sales  [日数=14]
//   node docs/analytics/fetch-kpi.mjs asc-analytics
//   node docs/analytics/fetch-kpi.mjs ga4        [日数=7]
//   node docs/analytics/fetch-kpi.mjs ga4-reward [日数=7]    # リワードの提示率・受諾率・先読み不足率（purpose 別）
//   node docs/analytics/fetch-kpi.mjs admob      [日数=7]
//   node docs/analytics/fetch-kpi.mjs all
//
// 認証（どちらも会長の Mac にだけ置いてある。リポジトリには入れない・出力にも出さない）:
//   ASC   : ~/.appstoreconnect/asc-key.json（key_id / issuer_id / key=.p8 の中身）。ベンダー番号は下の定数
//   Google: ~/.config/gcloud/application_default_credentials.json の refresh_token
//           （GA4・AdMob のスコープ付き。gcloud の標準クライアントではブロックされるため会長作成の OAuth クライアントで作ってある）
// 読み取りだけで、App Analytics のレポート依頼（POST）は `--create-analytics-request` を付けたときだけ行う。
import { createSign } from "node:crypto";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { gunzipSync } from "node:zlib";

const APP_ID = "6781719499"; // App Store の Apple ID（iTunes Lookup の trackId と同じ）
const VENDOR = "94327451"; // ASC「支払いと財務レポート」の左上
const GA4_PROPERTY = "549325996";
const BUILD_CHANNEL = "appstore"; // #347: GA4 は build_channel = appstore に絞って読む

const home = homedir();
const readJSON = (p) => JSON.parse(readFileSync(p.replace(/^~/, home), "utf8"));
const b64u = (b) => Buffer.from(b).toString("base64url");

// ---------- App Store Connect ----------
function ascToken() {
  const { key_id: kid, issuer_id: iss, key } = readJSON("~/.appstoreconnect/asc-key.json");
  const now = Math.floor(Date.now() / 1000);
  const head = b64u(JSON.stringify({ alg: "ES256", kid, typ: "JWT" }));
  const body = b64u(JSON.stringify({ iss, iat: now, exp: now + 15 * 60, aud: "appstoreconnect-v1" }));
  const sig = createSign("SHA256").update(`${head}.${body}`).sign({ key, dsaEncoding: "ieee-p1363" });
  return `${head}.${body}.${b64u(sig)}`;
}

async function asc(path, { method = "GET", json, raw = false } = {}) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: { Authorization: `Bearer ${ascToken()}`, ...(json ? { "Content-Type": "application/json" } : {}) },
    body: json ? JSON.stringify(json) : undefined,
  });
  if (!res.ok) throw new Error(`ASC ${method} ${path} → ${res.status} ${(await res.text()).slice(0, 300)}`);
  return raw ? Buffer.from(await res.arrayBuffer()) : res.json();
}

const ymd = (d) => d.toISOString().slice(0, 10);
// ASC の日次売上レポートの「日」は太平洋時間。UTC の日付で引くと JST の午前に直近の確定日を取り逃す
const ymdPT = (d) => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Los_Angeles" }).format(d);
const daysAgo = (n) => new Date(Date.now() - n * 86400000);
const tsv = (buf) => {
  const [head, ...rows] = gunzipSync(buf).toString("utf8").trim().split("\n").map((l) => l.split("\t"));
  return rows.map((r) => Object.fromEntries(head.map((h, i) => [h, r[i]])));
};
const table = (head, rows) => [`| ${head.join(" | ")} |`, `|${head.map(() => "---").join("|")}|`, ...rows.map((r) => `| ${r.join(" | ")} |`)].join("\n");

// 売上レポート（日次・SUMMARY）。Product Type 1/1F/1T=初回 DL、7/7F/7T=アップデート、3/3F/3T=再 DL。
// レポートの無い日は 404（確定前の日と、販売 0 件の日の両方）。404 以外の失敗は表に出して最後に例外にする。
async function ascSales(days = 14) {
  const FIRST = new Set(["1", "1F", "1T", "1E", "1EP", "1EU"]);
  const UPDATE = new Set(["7", "7F", "7T"]);
  const REDL = new Set(["3", "3F", "3T"]);
  const rows = [];
  let failed = 0;
  for (let i = days; i >= 1; i--) {
    const date = ymdPT(daysAgo(i));
    const q = new URLSearchParams({
      "filter[frequency]": "DAILY", "filter[reportType]": "SALES", "filter[reportSubType]": "SUMMARY",
      "filter[vendorNumber]": VENDOR, "filter[reportDate]": date, "filter[version]": "1_0",
    });
    try {
      const recs = tsv(await asc(`/v1/salesReports?${q}`, { raw: true })).filter((r) => r["Apple Identifier"] === APP_ID);
      const sum = (set) => recs.filter((r) => set.has(r["Product Type Identifier"])).reduce((a, r) => a + Number(r.Units || 0), 0);
      rows.push([date, sum(FIRST), sum(REDL), sum(UPDATE)]);
    } catch (e) {
      if (String(e).includes(" 404 ")) rows.push([date, "レポート無し", "（0件または未確定）", ""]);
      else { failed++; rows.push([date, `エラー: ${String(e).slice(0, 80)}`, "", ""]); }
    }
  }
  console.log("## ASC 売上レポート（日次・自社アプリのみ。単位: 件）\n");
  console.log(table(["日（太平洋時間）", "初回DL", "再DL", "アップデート"], rows));
  if (failed) throw new Error(`売上レポートの取得に ${failed} 日分失敗した（合計は確定値にならないので出さない）`);
  const n = (i) => rows.reduce((a, r) => a + (Number(r[i]) || 0), 0);
  console.log(`\n合計: 初回DL ${n(1)} / 再DL ${n(2)} / アップデート ${n(3)}`);
}

// App Analytics レポート。依頼（analyticsReportRequests）が無いと何も返らない。依頼は ONGOING を1本作れば以後は毎日たまる。
async function ascAnalytics(create) {
  const reqs = (await asc(`/v1/apps/${APP_ID}/analyticsReportRequests`)).data;
  console.log(`## ASC App Analytics（依頼 ${reqs.length} 件）\n`);
  if (!reqs.length) {
    if (!create) return console.log("依頼が無い。`--create-analytics-request` を付けて再実行すると ONGOING の依頼を1本作る（作成後、最初のレポートは1〜2日後）。");
    const r = await asc("/v1/analyticsReportRequests", {
      method: "POST",
      json: { data: { type: "analyticsReportRequests", attributes: { accessType: "ONGOING" },
        relationships: { app: { data: { type: "apps", id: APP_ID } } } } },
    });
    return console.log(`依頼を作成した: ${r.data.id}（ONGOING）。`);
  }
  for (const r of reqs) {
    const reports = (await asc(`/v1/analyticsReportRequests/${r.id}/reports?limit=200`)).data;
    console.log(`依頼 ${r.id}（${r.attributes.accessType}）: レポート ${reports.length} 種`);
    for (const rep of reports.filter((x) => ["App Store Discovery and Engagement Standard", "App Downloads Standard", "App Sessions Standard", "App Crashes"].includes(x.attributes.name))) {
      // 依頼の作成直後（最初のレポートが出来るまで 1〜2 日）は 401 で返ってくるので、失敗ではなく「生成前」として扱う
      const inst = await asc(`/v1/analyticsReports/${rep.id}/instances?filter[granularity]=DAILY&limit=7`).then((r) => r.data, (e) => (String(e).includes(" 401 ") ? null : Promise.reject(e)));
      if (!inst) { console.log(`- ${rep.attributes.category} / ${rep.attributes.name}: 生成前`); continue; }
      console.log(`- ${rep.attributes.category} / ${rep.attributes.name}: 日次インスタンス ${inst.length} 件`);
      for (const i of inst.slice(0, 7)) {
        const segs = (await asc(`/v1/analyticsReportInstances/${i.id}/segments`)).data;
        for (const s of segs) {
          const recs = tsv(await (await fetch(s.attributes.url)).arrayBuffer().then(Buffer.from));
          console.log(`  ${i.attributes.processingDate}: ${recs.length} 行（列: ${Object.keys(recs[0] || {}).join(", ")}）`);
        }
      }
    }
  }
}

// ---------- Google（GA4・AdMob）----------
async function googleToken() {
  const { client_id, client_secret, refresh_token } = readJSON("~/.config/gcloud/application_default_credentials.json");
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id, client_secret, refresh_token, grant_type: "refresh_token" }),
  });
  if (!res.ok) throw new Error(`Google token → ${res.status} ${(await res.text()).slice(0, 200)}`);
  return (await res.json()).access_token;
}

async function google(url, body) {
  const res = await fetch(url, {
    method: body ? "POST" : "GET",
    headers: { Authorization: `Bearer ${await googleToken()}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`${url} → ${res.status} ${(await res.text()).slice(0, 400)}`);
  return res.json();
}

const ga4Report = (body) => google(`https://analyticsdata.googleapis.com/v1beta/properties/${GA4_PROPERTY}:runReport`, body);
// build_channel = appstore に絞る（#347）。build_channel はユーザー範囲のカスタムディメンション（customUser:）。
const onlyAppStore = { filter: { fieldName: "customUser:build_channel", stringFilter: { matchType: "EXACT", value: BUILD_CHANNEL } } };
const andFilter = (...fs) => ({ andGroup: { expressions: fs } });
const evFilter = (...names) => ({ filter: { fieldName: "eventName", inListFilter: { values: names } } });
const dateRange = (days) => [{ startDate: `${days}daysAgo`, endDate: "yesterday" }];

async function ga4(days = 7) {
  const head = `build_channel = ${BUILD_CHANNEL}・直近 ${days} 日（昨日まで）`;
  const total = await ga4Report({
    dateRanges: dateRange(days), metrics: [{ name: "activeUsers" }, { name: "eventCount" }],
    dimensionFilter: onlyAppStore,
  });
  const m = (total.rows?.[0]?.metricValues || []).map((v) => v.value);
  console.log(`## GA4（${head}）\n\nアクティブユーザー ${m[0] ?? 0} / イベント ${m[1] ?? 0}\n`);
  const ev = await ga4Report({
    dateRanges: dateRange(days), dimensions: [{ name: "eventName" }],
    metrics: [{ name: "eventCount" }, { name: "totalUsers" }], dimensionFilter: onlyAppStore,
    orderBys: [{ metric: { metricName: "eventCount" }, desc: true }], limit: 30,
  });
  console.log(table(["イベント", "回数", "人数"], (ev.rows || []).filter((r) => Number(r.metricValues[0].value) > 0).map((r) => [r.dimensionValues[0].value, r.metricValues[0].value, r.metricValues[1].value])));
  const g = await ga4Report({
    dateRanges: dateRange(days), dimensions: [{ name: "customEvent:game_id" }],
    metrics: [{ name: "eventCount" }, { name: "totalUsers" }],
    dimensionFilter: andFilter(onlyAppStore, evFilter("game_start")),
    orderBys: [{ metric: { metricName: "eventCount" }, desc: true }], limit: 50,
  });
  console.log("\n### ゲーム別 game_start（回数・人数。麻雀は1局でなく1対局で1回なので回数の単位は揃わない）\n");
  console.log(table(["game_id", "回数", "人数"], (g.rows || []).map((r) => [r.dimensionValues[0].value, r.metricValues[0].value, r.metricValues[1].value])));
}

// リワードの漏斗。式は docs/spec-app.md「解析仕様」の reward_offer の項（#780）。
async function ga4Reward(days = 7) {
  const rep = (names, dims) => ga4Report({
    dateRanges: dateRange(days), dimensions: dims.map((name) => ({ name })), metrics: [{ name: "eventCount" }],
    dimensionFilter: andFilter(onlyAppStore, evFilter(...names)), limit: 500,
  });
  const offers = await rep(["reward_offer"], ["customEvent:purpose", "customEvent:result"]);
  const tally = {};
  for (const r of offers.rows || []) {
    const [purpose, result] = r.dimensionValues.map((d) => d.value);
    (tally[purpose] ||= { accepted: 0, declined: 0, not_ready: 0 })[result] = Number(r.metricValues[0].value);
  }
  const req = await rep(["reward_request", "reward_ad"], ["eventName", "customEvent:purpose"]);
  const count = (ev, p) => Number(req.rows?.find((r) => r.dimensionValues[0].value === ev && r.dimensionValues[1].value === p)?.metricValues[0].value || 0);
  const pct = (a, b) => (b ? `${((100 * a) / b).toFixed(1)}%` : "—");
  console.log(`## リワード広告の漏斗（build_channel = ${BUILD_CHANNEL}・直近 ${days} 日。reward_offer は v1.1.7 以降のデータのみ）\n`);
  console.log(table(
    ["purpose", "提示", "accepted", "not_ready", "declined", "受諾率", "先読み不足率", "reward_request", "reward_ad", "完了率"],
    Object.entries(tally).map(([p, t]) => {
      const offer = t.accepted + t.declined + t.not_ready, acc = t.accepted + t.not_ready;
      return [p, offer, t.accepted, t.not_ready, t.declined, pct(acc, offer), pct(t.not_ready, acc),
        count("reward_request", p), count("reward_ad", p), pct(count("reward_ad", p), count("reward_request", p))];
    }),
  ));
  const per = await ga4Report({
    dateRanges: dateRange(days), dimensions: [{ name: "customEvent:game_id" }, { name: "eventName" }, { name: "customEvent:result" }],
    metrics: [{ name: "eventCount" }],
    dimensionFilter: andFilter(onlyAppStore, evFilter("game_start", "game_end")), limit: 1000,
  });
  const base = {};
  for (const r of per.rows || []) {
    const [g, ev, res] = r.dimensionValues.map((d) => d.value), c = Number(r.metricValues[0].value);
    const b = (base[g] ||= { start: 0, loss: 0 });
    if (ev === "game_start") b.start += c;
    else if (res === "loss") b.loss += c;
  }
  console.log("\n### 提示率の分母（game_id 別。コンティニュー・復活は loss、待った・戻す・並べ替えは game_start で割る）\n");
  console.log(table(["game_id", "game_start", "game_end(loss)"], Object.entries(base).sort((a, b) => b[1].start - a[1].start).map(([g, b]) => [g, b.start, b.loss])));
  console.log("\n完了率の分母（reward_request）は、確認を挟まず広告へ進む面（ナンプレ等のヒント）や再生の途中離脱で purpose と揃わず、100% を超えることがある。\n提示率は、purpose と分母のゲーム・場面が 1 対 1 でないため自動では出さない。上の分母の表から場面ごとに手で割る。");
}

async function admob(days = 7) {
  const acc = (await google("https://admob.googleapis.com/v1/accounts")).account?.[0];
  if (!acc) throw new Error("AdMob アカウントが見えない");
  const d = (n) => { const x = daysAgo(n); return { year: x.getUTCFullYear(), month: x.getUTCMonth() + 1, day: x.getUTCDate() }; };
  const res = await google(`https://admob.googleapis.com/v1/${acc.name}/networkReport:generate`, {
    reportSpec: {
      dateRange: { startDate: d(days), endDate: d(1) },
      dimensions: ["AD_UNIT"],
      metrics: ["ESTIMATED_EARNINGS", "IMPRESSIONS", "AD_REQUESTS", "MATCH_RATE", "IMPRESSION_RPM"],
      localizationSettings: { currencyCode: "JPY" },
    },
  });
  const rows = res.filter((x) => x.row).map((x) => x.row);
  console.log(`## AdMob（直近 ${days} 日（昨日まで）・通貨 JPY・推定。アプリ・ビルドで絞れないため GA4（appstore 限定）とは母集団が違う）\n`);
  const v = (r, k) => r.metricValues[k] || {};
  console.log(table(["広告ユニット", "推定収益(円)", "表示回数", "リクエスト", "マッチ率", "eCPM(円)"], rows.map((r) => [
    `${r.dimensionValues.AD_UNIT.displayLabel}（…${r.dimensionValues.AD_UNIT.value.slice(-4)}）`,
    ((Number(v(r, "ESTIMATED_EARNINGS").microsValue || 0)) / 1e6).toFixed(0),
    v(r, "IMPRESSIONS").integerValue || 0, v(r, "AD_REQUESTS").integerValue || 0,
    `${((Number(v(r, "MATCH_RATE").doubleValue || 0)) * 100).toFixed(0)}%`,
    Number(v(r, "IMPRESSION_RPM").doubleValue || 0).toFixed(0),
  ])));
}

// ---------- main ----------
const [cmd = "all", ...rest] = process.argv.slice(2);
const n = Number(rest.find((a) => /^\d+$/.test(a))) || undefined;
const jobs = {
  "asc-sales": () => ascSales(n),
  "asc-analytics": () => ascAnalytics(rest.includes("--create-analytics-request")),
  ga4: () => ga4(n),
  "ga4-reward": () => ga4Reward(n),
  admob: () => admob(n),
};
const run = cmd === "all" ? ["asc-sales", "ga4", "ga4-reward", "admob"] : [cmd];
if (run.some((c) => !jobs[c])) { console.error(`使い方: ${Object.keys(jobs).join(" | ")} | all`); process.exit(2); }
let failed = false;
for (const c of run) {
  try { await jobs[c](); } catch (e) { failed = true; console.error(`\n[${c}] 失敗: ${e.message}`); }
  console.log();
}
process.exit(failed ? 1 : 0);
