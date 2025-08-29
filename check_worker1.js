// Node.js v18 以降なら node-fetch 不要
// それ以前は: npm install node-fetch
const fetch = require('node-fetch');

// Workers の URL を指定
const TARGET_URL = 'https://rustwasm-fullstack-app.sumitomo0210.workers.dev/api/quote?codes=6758.T,5016.T';
const INTERVAL_SECONDS = 60; // 60秒ごとに更新

console.log(`Workers 経由で株価監視開始: ${TARGET_URL}`);
console.log(`${INTERVAL_SECONDS}秒ごとに更新します。\n`);

const performCheck = async () => {
  const timestamp = new Date().toLocaleString("ja-JP");

  try {
    // Workers の URL に fetch
    const response = await fetch(TARGET_URL, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36"
      }
    });

    if (!response.ok) {
      console.error(`[${timestamp}] APIエラー: ${response.status} ${response.statusText}`);
      return;
    }

    // JSON にパース
    const jsonResponse = await response.json();
    const data = jsonResponse.data || [];

    // 株価を整形して出力
    data.forEach(q => {
      console.log(
        `[${timestamp}] ${q.code} ${q.name} 現在値: ${q.current_value}円 (前日比: ${q.previous_day_change}, ${q.change_rate})`
      );
    });

  } catch (error) {
    console.error(`[${timestamp}] fetchエラー: ${error}`);
  }

  console.log('--------------------------------------------------');
};

// 最初に一度実行してからインターバルで定期取得
performCheck();
setInterval(performCheck, INTERVAL_SECONDS * 1000);
