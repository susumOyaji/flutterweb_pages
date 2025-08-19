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

    // Pages FunctionへのリクエストURLからクエリパラメータを取得
    const url = new URL(context.request.url);
    const codes = url.searchParams.get('codes');

    let workerFetchUrl = baseUrl + 'api/quote';
    if (codes) {
      workerFetchUrl += `?codes=${encodeURIComponent(codes)}`;
    }

    const fetchOptions = {
      method: context.request.method,
      headers: new Headers(context.request.headers),
    };

    if (context.request.method !== 'GET' && context.request.body) {
      fetchOptions.body = context.request.body;
    }

    fetchOptions.headers.delete('Host');

    const workerResponse = await fetch(workerFetchUrl, fetchOptions);
    const workerResponseText = await workerResponse.text();

    let workerData;
    try {
      workerData = JSON.parse(workerResponseText);
    } catch (jsonError) {
      return new Response(JSON.stringify({
        status: 'error',
        message: `既存Workerからのレスポンスが不正なJSONです: ${jsonError.message}`,
        rawResponse: workerResponseText,
      }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({
      status: workerResponse.ok ? 'success' : 'error',
      data: workerData,
      source: 'existing-worker',
      message: workerResponse.ok ? 'データ取得成功' : `既存Workerからのエラー: ${workerResponse.statusText || '不明なエラー'}`,
    }), {
      status: workerResponse.status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

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