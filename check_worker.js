const fetch = require('node-fetch');

// --- 設定 ---
const TARGET_URL = 'https://rustwasm-fullstack-app.sumitomo0210.workers.dev/api/quote?codes=6758.T';
const INTERVAL_SECONDS = 60; // 60秒ごとに実行
// ------------

console.log(`以下のURLへの定期的なチェックを開始します: ${TARGET_URL}`);
console.log(`${INTERVAL_SECONDS}秒ごとに実行します。`);
console.log('停止するには Ctrl+C を押してください。\n');
console.log('--------------------------------------------------');

const performCheck = async () => {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] リクエストを送信中...`);

    try {
        const response = await fetch(TARGET_URL, {
            headers: {
                // ブラウザのUser-Agentを模倣
                //'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'

                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36"
            }


        });

        const responseBody = await response.text();
        console.log(`[${timestamp}] ステータス: ${response.status} ${response.statusText}`);

        // 可読性のためにJSONとしてパースを試みる。失敗したらテキストとして出力。
        try {
            const jsonResponse = JSON.parse(responseBody);
            console.log(`[${timestamp}] レスポンスボディ (JSON):\n${JSON.stringify(jsonResponse, null, 2)}`);
        } catch (e) {
            console.log(`[${timestamp}] レスポンスボディ (Text):\n${responseBody}`);
        }

    } catch (error) {
        console.error(`[${timestamp}] fetch中にエラーが発生しました:`);
        console.error(error);
    } finally {
        console.log('--------------------------------------------------');
    }
};

// 最初に一度即時実行し、その後タイマーを設定
performCheck();
setInterval(performCheck, INTERVAL_SECONDS * 1000);
