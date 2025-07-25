import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';



// トップレベルで定義
const String portfolioKey = 'portfolio_items';
late List<PortfolioItem> initialPortfolioItems;


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final List<String>? jsonStrings = prefs.getStringList(portfolioKey);
  initialPortfolioItems = jsonStrings
          ?.map((jsonString) =>
              PortfolioItem.fromJson(json.decode(jsonString)))
          .toList() ??
      [];

  runApp(const MyApp());
}

// --- Data Models ---
class FinancialData {
  final String name;
  final String code;
  final String updateTime;
  final String currentValue;
  final String? bidValue;
  final String previousDayChange;
  final String changeRate;

  const FinancialData({
    required this.name,
    required this.code,
    required this.updateTime,
    required this.currentValue,
    this.bidValue,
    required this.previousDayChange,
    required this.changeRate,
  });

  factory FinancialData.fromJson(Map<String, dynamic> json) {
    return FinancialData(
      name: json['name'] ?? 'N/A',
      code: json['code'] ?? 'N/A',
      updateTime: json['update_time'] ?? '--:--',
      currentValue: json['current_value'] ?? '-',
      bidValue: json['bid_value'],
      previousDayChange: json['previous_day_change'] ?? '-',
      changeRate: json['change_rate'] ?? '-',
    );
  }
}

class PortfolioItem {
  final String code;
  final int quantity;
  final double acquisitionPrice;

  const PortfolioItem({
    required this.code,
    required this.quantity,
    required this.acquisitionPrice,
  });

  // PortfolioItemをJSONに変換
  Map<String, dynamic> toJson() => {
        'code': code,
        'quantity': quantity,
        'acquisitionPrice': acquisitionPrice,
      };

  // JSONからPortfolioItemを生成
  factory PortfolioItem.fromJson(Map<String, dynamic> json) {
    return PortfolioItem(
      code: json['code'] as String,
      quantity: json['quantity'] as int,
      acquisitionPrice: (json['acquisitionPrice'] as num).toDouble(),
    );
  }
}

// 表示用の結合データモデル
class PortfolioDisplayData {
  final FinancialData financialData;
  final PortfolioItem portfolioItem;

  const PortfolioDisplayData({
    required this.financialData,
    required this.portfolioItem,
  });
}

// --- App ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Stock Ticker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        cardTheme: CardTheme(
          elevation: 4.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
        ),
      ),
      home: const MyHomePage(title: 'Market & Portfolio'),
    );
  }
}

// --- Home Page ---
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final List<String> _defaultCodes = const ['^DJI', '998407.O', 'USDJPY=X'];
  List<PortfolioItem> _portfolioItems = []; // 型をPortfolioItemに変更

  List<FinancialData> _defaultFinancialData = [];
  List<PortfolioDisplayData> _portfolioDisplayData = []; // 型をPortfolioDisplayDataに変更
  String _statusMessage = '';
  String _rawResponse = '';

  @override
  void initState() {
    super.initState();
    _portfolioItems = List.from(initialPortfolioItems); // 初期データをコピー
    _callWorker();
  }

  // --- Data Persistence ---
  Future<void> _loadPortfolio() async {
    // この関数はmain()で呼び出されるため、ここでは不要
  }

  Future<void> _savePortfolio() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsonStrings =
        _portfolioItems.map((item) => json.encode(item.toJson())).toList();
    await prefs.setStringList(portfolioKey, jsonStrings);
  }

  // --- Stock Management ---
  Future<void> _addStock(String code, int quantity, double acquisitionPrice) async {
    final upperCaseCode = code.toUpperCase();
    if (upperCaseCode.isNotEmpty && quantity > 0 && acquisitionPrice >= 0) {
      setState(() {
        _portfolioItems.add(PortfolioItem(
          code: upperCaseCode,
          quantity: quantity,
          acquisitionPrice: acquisitionPrice,
        ));
      });
      await _savePortfolio();
      // 保存が確実に完了するのを待つためのわずかな遅延
      await Future.delayed(const Duration(milliseconds: 100));
      await _callWorker();
    }
  }

  Future<void> _removeStock(int index) async {
    setState(() {
      _portfolioItems.removeAt(index);
    });
    await _savePortfolio();
    // 保存が確実に完了するのを待つためのわずかな遅延
    await Future.delayed(const Duration(milliseconds: 100));
    await _callWorker(); // ポートフォリオの表示を更新するために再呼び出し
  }

  // --- API Call ---
  Future<void> _callWorker() async {
    setState(() {
      _statusMessage = 'Loading...';
    });

    final allCodesSet = <String>{..._defaultCodes, ..._portfolioItems.map((e) => e.code)};
    if (allCodesSet.isEmpty) {
        setState(() {
            _statusMessage = 'No stocks to display.';
            _defaultFinancialData = [];
            _portfolioDisplayData = [];
        });
        return;
    }

    final codes = allCodesSet.join(',');
    final workerUrl = 'https://rustwasm-fullstack-app.sumitomo0210.workers.dev/api/quote?codes=$codes';

    try {
      final response = await http.get(Uri.parse(workerUrl));
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        final List<FinancialData> fetchedData = (decoded['data'] as List)
            .map((item) => FinancialData.fromJson(item))
            .toList();

        final Map<String, FinancialData> dataMap = {
          for (var data in fetchedData) data.code: data
        };

        setState(() {
          _defaultFinancialData = _defaultCodes
              .map((code) => dataMap[code])
              .whereType<FinancialData>()
              .toList();

          _portfolioDisplayData = _portfolioItems
              .map((item) {
                final financialData = dataMap[item.code];
                return financialData != null
                    ? PortfolioDisplayData(financialData: financialData, portfolioItem: item)
                    : null;
              })
              .whereType<PortfolioDisplayData>()
              .toList();

          _statusMessage = '';
          const jsonEncoder = JsonEncoder.withIndent('  ');
          _rawResponse = jsonEncoder.convert(decoded);
        });
      } else {
        setState(() {
          _statusMessage = 'Error: ${response.statusCode}';
          _rawResponse = response.body;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _rawResponse = e.toString();
      });
    }
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddStockDialog,
            tooltip: 'Add Stock to Portfolio',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _callWorker,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: ListView(
        children: <Widget>[
          if (_statusMessage.isNotEmpty && _defaultFinancialData.isEmpty && _portfolioDisplayData.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                _statusMessage,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
          // Default Market Data Section
          if (_defaultFinancialData.isNotEmpty)
            _buildSectionHeader(context, 'Default Market Data'),
          if (_defaultFinancialData.isNotEmpty)
            _buildGridView(_defaultFinancialData, false, true),

          // My Portfolio Section
          _buildSectionHeader(context, 'My Portfolio'),
          if (_portfolioDisplayData.isNotEmpty)
            _buildPortfolioGridView(_portfolioDisplayData, true, false)
          else if (_portfolioItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Center(child: Text('Your portfolio is empty. Add stocks using the '+' button.')),
            ),

          // Raw Response Section
          if (_rawResponse.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 16.0, 8.0, 8.0),
              child: ExpansionTile(
                title: const Text('Raw Response'),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    color: Colors.grey.shade200,
                    child: SelectableText(_rawResponse),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildGridView(List<FinancialData> data, bool showRemoveButton, bool isDefaultSection) {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      shrinkWrap: true, // Important for ListView
      physics: const NeverScrollableScrollPhysics(), // Important for ListView
      gridDelegate: isDefaultSection
          ? const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, // デフォルト銘柄は常に3列
              childAspectRatio: 3 / 1.0, // アイテムの幅と高さの比率
              crossAxisSpacing: 16, // 水平方向のスペース
              mainAxisSpacing: 16, // 垂直方向のスペース
            )
          : const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420, // ポートフォリオは最大5個表示されるように調整
              childAspectRatio: 3 / 1.0, // アイテムの幅と高さの比率
              crossAxisSpacing: 16, // 水平方向のスペース
              mainAxisSpacing: 16, // 垂直方向のスペース
            ),
      itemCount: data.length,
      itemBuilder: (context, index) {
        final item = data[index];
        return StockCard(
          financialData: item,
          onRemove: showRemoveButton ? () => _removeStock(index) : null,
        );
      },
    );
  }

  // ポートフォリオ専用のGridView (PortfolioDisplayDataを受け取る)
  Widget _buildPortfolioGridView(List<PortfolioDisplayData> data, bool showRemoveButton, bool isDefaultSection) {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: isDefaultSection
          ? const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 3 / 2.5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            )
          : const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420,
              childAspectRatio: 3 / 2.5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
      itemCount: data.length,
      itemBuilder: (context, index) {
        final item = data[index];
        return StockCard(
          financialData: item.financialData,
          portfolioItem: item.portfolioItem,
          onRemove: showRemoveButton ? () => _removeStock(index) : null,
        );
      },
    );
  }

  void _showAddStockDialog() {
    final codeController = TextEditingController();
    final quantityController = TextEditingController(text: '1');
    final priceController = TextEditingController(text: '0.0');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Stock to Portfolio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Stock Code (e.g., AAPL)'),
            ),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Quantity'),
            ),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'Acquisition Price'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final code = codeController.text;
              final quantity = int.tryParse(quantityController.text) ?? 0;
              final price = double.tryParse(priceController.text) ?? 0.0;
              _addStock(code, quantity, price);
              Navigator.of(context).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// --- Stock Card Widget ---
class StockCard extends StatelessWidget {
  final FinancialData financialData;
  final PortfolioItem? portfolioItem; // ポートフォリオアイテムはオプション
  final VoidCallback? onRemove;

  const StockCard({
    super.key,
    required this.financialData,
    this.portfolioItem,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final changeColor = financialData.previousDayChange.startsWith('-') ? Colors.red : Colors.green;

    // 評価額と損益の計算
    double? currentValueNum = double.tryParse(financialData.currentValue.replaceAll(',', ''));
    double? estimatedValue;
    double? profitLoss;
    Color? profitLossColor;

    if (portfolioItem != null && currentValueNum != null) {
      estimatedValue = currentValueNum * portfolioItem!.quantity;
      profitLoss = (currentValueNum - portfolioItem!.acquisitionPrice) * portfolioItem!.quantity;
      profitLossColor = profitLoss >= 0 ? Colors.green : Colors.red;
    }

    return Card(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 銘柄名とコード
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      financialData.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${financialData.code} (${financialData.updateTime})',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
                // 株価情報
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      financialData.currentValue,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          financialData.previousDayChange,
                          style: TextStyle(color: changeColor, fontSize: 16),
                        ),
                        Text(
                          '(${financialData.changeRate}%)',
                          style: TextStyle(color: changeColor),
                        ),
                      ],
                    ),
                  ],
                ),
                // ポートフォリオ情報 (存在する場合のみ表示)
                if (portfolioItem != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      Text('Quantity: ${portfolioItem!.quantity}'),
                      Text('Acq. Price: ${portfolioItem!.acquisitionPrice.toStringAsFixed(2)}'),
                      if (estimatedValue != null) Text('Est. Value: ${estimatedValue.toStringAsFixed(2)}'),
                      if (profitLoss != null) Text(
                        'P/L: ${profitLoss.toStringAsFixed(2)}',
                        style: TextStyle(color: profitLossColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: onRemove,
                tooltip: 'Remove from Portfolio',
              ),
            ),
        ],
      ),
    );
  }
}


