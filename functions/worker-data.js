// functions/api/worker-data.js
// Cloudflare Pages Function: 既存のWorkerからのデータ取得を仲介

// CORSヘッダーを定義
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, HEAD, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export async function onRequest(context) {
  // OPTIONSメソッド（プリフライトリクエスト）への対応
  if (context.request.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // 既存のWorkerのベースURL
    const baseUrl = 'https://rustwasm-fullstack-app.sumitomo0210.workers.dev/';

    // Pages FunctionへのリクエストURLを取得
    const url = new URL(context.request.url);

    // URLのクエリ文字列（?以降）をそのまま利用する
    const search = url.search;
    let workerFetchUrl = baseUrl + 'api/quote' + search;

    const fetchOptions = {
      method: 'GET', // メソッドをGETに固定
      headers: {     // ヘッダーを最小限に固定
        'User-Agent': 'Cloudflare-Worker-Proxy/1.0'
      },
    };

    const workerResponse = await fetch(workerFetchUrl, fetchOptions);

    // Workerからのレスポンスが成功した場合
    if (workerResponse.ok) {
      const workerResponseText = await workerResponse.text();
      // CORSヘッダーを付与しつつ、Workerのレスポンスボディをそのまま返す
      return new Response(workerResponseText, {
        status: workerResponse.status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    } else {
      // Workerからのレスポンスが失敗した場合
      const workerResponseText = await workerResponse.text();
      return new Response(JSON.stringify({
        status: 'error',
        message: `既存Workerからのエラー: ${workerResponse.statusText || '不明なエラー'}`,
        rawResponse: workerResponseText,
      }), {
        status: workerResponse.status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
  } catch (error) {
    return new Response(JSON.stringify({
      status: 'error',
      message: `Pages Function内部エラー: ${error.message}`,
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}