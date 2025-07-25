// functions/api/worker-data.js
// Cloudflare Pages Function: 既存のWorkerからのデータ取得を仲介
export async function onRequest(context) {
  try {
    // 既存のWorkerのベースURL
    const baseUrl = 'https://rustwasm-fullstack-app.sumitomo0210.workers.dev/';

    // Pages FunctionへのリクエストURLからクエリパラメータを取得
    // 例: /api/worker-data?codes=6758.T,^DJI
    const url = new URL(context.request.url);
    const codes = url.searchParams.get('codes'); // 'codes' パラメータの値を取得

    let workerFetchUrl = baseUrl + 'api/quote';
    // 'codes' パラメータが存在すれば、既存WorkerのURLに付与
    // 既存Workerも同じパラメータ名 'codes' を期待すると仮定
    if (codes) {
      workerFetchUrl += `?codes=${encodeURIComponent(codes)}`;
    }

   
    // 既存のWorkerへのリクエストオプションを設定
    const fetchOptions = {
      method: context.request.method, // Pages Functionへのリクエストメソッドをそのまま転送
      headers: new Headers(context.request.headers), // Pages Functionへのリクエストヘッダーをコピー
    };

    // GETリクエスト以外の場合のみリクエストボディを含める
    // GETリクエストにボディを含めるとエラーになる可能性があるため
    if (context.request.method !== 'GET' && context.request.body) {
        fetchOptions.body = context.request.body;
    }

    // Hostヘッダーは転送しない方が安全な場合が多い
    // ターゲットのWorkerが自身のホスト名を期待するため
    fetchOptions.headers.delete('Host');

    // 既存のWorkerへのリクエストを転送
    const workerResponse = await fetch(workerFetchUrl, fetchOptions);

    // 既存のWorkerからのレスポンスをテキストとして取得し、ログに出力
    const workerResponseText = await workerResponse.text();
    console.log('Worker Response Text:', workerResponseText);

    let workerData;
    try {
      workerData = JSON.parse(workerResponseText);
    } catch (jsonError) {
      console.error('Failed to parse Worker response as JSON:', jsonError);
      // JSONパースエラーが発生した場合、エラーレスポンスを返す
      return new Response(JSON.stringify({
          status: 'error',
          message: `既存Workerからのレスポンスが不正なJSONです: ${jsonError.message}`,
          rawResponse: workerResponseText // 生のレスポンスを含める
      }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }

    // フロントエンドが期待するJSON形式にPages Functionでラップして返す
    // { status: 'success'/'error', data: [...], source: '...', message: '...' }
    return new Response(JSON.stringify({
      status: workerResponse.ok ? 'success' : 'error', // 既存WorkerのHTTPステータスに基づいて成功/失敗を判断
      data: workerData, // 既存Workerから取得したデータ本体を 'data' キーに入れる
      source: 'existing-worker',
      message: workerResponse.ok ? 'データ取得成功' : `既存Workerからのエラー: ${workerResponse.statusText || '不明なエラー'}`
    }), {
      headers: { 'Content-Type': 'application/json' }, // レスポンスヘッダーをJSONに設定
      status: workerResponse.status // 既存WorkerのステータスコードをPages Functionのレスポンスに反映
    });

  } catch (error) {
    // Pages Function自体で発生したエラー（例: fetch失敗、JSONパース失敗など）
    console.error('Pages Function内部エラー:', error);
    return new Response(JSON.stringify({
        status: 'error',
        message: `Pages Function内部エラー: ${error.message}`
    }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
}