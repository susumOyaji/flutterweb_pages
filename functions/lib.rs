use scraper::{Html, Selector};
use serde::Serialize;
use worker::{event, console_log, Env, Request, Response, Result, Method, Context};
use futures::future::join_all;

// レスポンスのJSON形式を定義
#[derive(Serialize)]
struct ApiResponse {
    status: String,
    data: Vec<FinancialData>,
}

#[derive(Serialize, Debug, PartialEq, Clone)]
pub struct FinancialData {
    name: Option<String>,
    code: Option<String>,
    update_time: Option<String>,
    current_value: Option<String>,
    bid_value: Option<String>,
    previous_day_change: Option<String>,
    change_rate: Option<String>,
}

// &str ではなく String を受け取るように変更
pub fn parse_financial_data(html_content: &str, url: String) -> FinancialData {
    let document = Html::parse_document(html_content);

    // セレクタをまとめてパース
    let name_selector = Selector::parse("h2[class*=\"PriceBoard__name\"]").expect("Failed to parse name selector");
    let code_selector = Selector::parse("span[class*=\"PriceBoard__code\"]").expect("Failed to parse code selector");
    let time_selector = Selector::parse("time").expect("Failed to parse time selector");
    let price_selector = Selector::parse("span[class*=\"PriceBoard__price\"] span[class*=\"StyledNumber__value\"]").expect("Failed to parse price selector");
    let fx_price_selector = Selector::parse("div > span").expect("Failed to parse fx price selector");
    let change_selector = Selector::parse("div[class*=\"PriceChangeLabel\"] span[class*=\"StyledNumber__value\"]").expect("Failed to parse change selector");
    let bid_term_selector = Selector::parse("dt[class*=\"_FxPriceBoard__term\"]").expect("Failed to parse bid term selector");
    let dd_selector = Selector::parse("dd[class*=\"_FxPriceBoard__description\"]").expect("Failed to parse dd selector");
    let price_span_selector = Selector::parse("span[class*=\"_FxPriceBoard__price\"]").expect("Failed to parse price span selector");
    let dd_plain_selector = Selector::parse("dd").expect("Failed to parse dd plain selector");
    let span_selector = Selector::parse("span").expect("Failed to parse span selector");

    // テキスト取得のヘルパー
    let get_text = |el: Option<scraper::ElementRef>| el.map(|e| e.text().collect::<String>());

    let mut data = FinancialData {
        name: get_text(document.select(&name_selector).next()),
        code: if !url.contains("USDJPY=FX") {
            get_text(document.select(&code_selector).next())
        } else {
            Some("USDJPY=FX".to_string())
        },
        update_time: get_text(document.select(&time_selector).next()),
        current_value: None,
        bid_value: None,
        previous_day_change: None,
        change_rate: None,
    };

    if url.contains("USDJPY=FX") {
        data.current_value = get_text(document.select(&fx_price_selector).next());
        for dt in document.select(&bid_term_selector) {
            if dt.text().collect::<String>().trim() == "Bid（売値）" {
                if let Some(dl) = dt.parent().and_then(scraper::ElementRef::wrap) {
                    data.bid_value = get_text(dl.select(&dd_selector).next().and_then(|dd| dd.select(&price_span_selector).next()));
                    break;
                }
            }
        }
        for dt in document.select(&bid_term_selector) {
            if dt.text().collect::<String>().trim() == "Change（始値比）" {
                if let Some(dl) = dt.parent().and_then(scraper::ElementRef::wrap) {
                    data.change_rate = get_text(dl.select(&dd_plain_selector).next().and_then(|dd| dd.select(&span_selector).next()));
                    break;
                }
            }
        }
    } else {
        data.current_value = get_text(document.select(&price_selector).next());
        let changes: Vec<String> = document.select(&change_selector).map(|el| el.text().collect()).collect();
        if changes.len() >= 2 {
            data.previous_day_change = Some(changes[0].clone());
            data.change_rate = Some(changes[1].clone());
        }
    }
    data
}

// &str ではなく String を受け取るように変更
pub async fn fetch_financial_data(url: String) -> Result<FinancialData> {
    console_log!("Fetching financial data from: {}", &url);
    // URLのパースに失敗した場合、expectでpanicさせる代わりにErrを返す
    let parsed_url = match url.parse() {
        Ok(u) => u,
        Err(e) => {
            console_log!("Failed to parse URL: {}, error: {}", url, e);
            return Err(worker::Error::from(format!("URL parse error: {}", e)));
        }
    };
    let html_content = worker::Fetch::Url(parsed_url).send().await?.text().await?;
    let data = parse_financial_data(&html_content, url);
    Ok(data)
}

#[event(fetch)]
async fn fetch(req: Request, _env: Env, _ctx: Context) -> Result<Response> {
    if req.method() == Method::Options {
        let mut headers = worker::Headers::new();
        headers.set("Access-Control-Allow-Origin", "*")?;
        headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")?;
        headers.set("Access-Control-Allow-Headers", "Content-Type")?;
        return Ok(Response::empty()?.with_headers(headers));
    }

    let url = req.url()?;
    if url.path() == "/api/quote" {
        let query_params: std::collections::HashMap<_, _> = url.query_pairs().into_owned().collect();
        
        if let Some(codes_str) = query_params.get("codes") {
            let codes: Vec<&str> = codes_str.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()).collect();
            
            let futures: Vec<_> = codes.into_iter().map(|code| {
                let yahoo_url = format!("https://finance.yahoo.co.jp/quote/{}", code);
                // & を外して所有権を渡す
                fetch_financial_data(yahoo_url)
            }).collect();
            
            let results: Vec<FinancialData> = join_all(futures).await
                .into_iter()
                .filter_map(Result::ok)
                .collect();

            let api_response = ApiResponse {
                status: "success".to_string(),
                data: results,
            };

            let mut response = Response::from_json(&api_response)?;
            response.headers_mut().set("Access-Control-Allow-Origin", "*")?;
            Ok(response)

        } else {
            Response::error("Query parameter 'codes' is required.", 400)
        }
    } else {
        Response::error("Not Found", 404)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_stock_data() {
        let sample_html = r#"
            <!DOCTYPE html>
            <html>
            <body>
                <h2 class=\"PriceBoard__name__166W\">テスト株式会社</h2>
                <span class=\"PriceBoard__code__2wso\">(9999.T)</span>
                <div>
                    <span class=\"PriceBoard__price__2f94\"><span class=\"StyledNumber__value__3rXW\">1,234</span></span>
                </div>
                <div class=\"PriceChangeLabel__label__3o3i\">
                    <span class=\"StyledNumber__value__3rXW\">+56</span>
                    <span class=\"StyledNumber__value__3rXW\">(+4.75%)</span>
                </div>
                <time datetime=\"2025-07-19T15:00:00+09:00\">15:00</time>
            </body>
            </html>
        "#;
        let url = "https://finance.yahoo.co.jp/quote/9999.T".to_string();
        let expected_data = FinancialData {
            name: Some("テスト株式会社".to_string()),
            code: Some("(9999.T)".to_string()),
            update_time: Some("15:00".to_string()),
            current_value: Some("1,234".to_string()),
            bid_value: None,
            previous_day_change: Some("+56".to_string()),
            change_rate: Some("(+4.75%)".to_string()),
        };

        let result_data = parse_financial_data(sample_html, url);
        assert_eq!(result_data, expected_data);
    }

    #[test]
    fn test_parse_usdjpy_data() {
        let sample_html = r#"
            <!DOCTYPE html>
            <html>
            <body>
                <h2 class=\"PriceBoard__name__166W\">米ドル/円</h2>
                <div>
                    <span data-testid=\"text-for-price\">152.50</span>
                </div>
                <time>12:00</time>
            </body>
            </html>
        "#;
        let url = "https://finance.yahoo.co.jp/quote/USDJPY=FX".to_string();
        let expected_data = FinancialData {
            name: Some("米ドル/円".to_string()),
            code: Some("USDJPY=FX".to_string()),
            update_time: Some("12:00".to_string()),
            current_value: Some("152.50".to_string()),
            bid_value: None,
            previous_day_change: None,
            change_rate: None,
        };

        let result_data = parse_financial_data(sample_html, url);
        assert_eq!(result_data, expected_data);
    }
}