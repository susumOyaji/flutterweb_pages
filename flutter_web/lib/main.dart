import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:popover/popover.dart'; // popoverをインポート
import 'package:shared_preferences/shared_preferences.dart';

// トップレベルで定義
const String portfolioKey = 'portfolio_items';
const String updateIntervalKey = 'update_interval'; // キーをここに移動
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

  Map<String, dynamic> toJson() => {
        'code': code,
        'quantity': quantity,
        'acquisitionPrice': acquisitionPrice,
      };

  factory PortfolioItem.fromJson(Map<String, dynamic> json) {
    return PortfolioItem(
      code: json['code'] as String,
      quantity: json['quantity'] as int,
      acquisitionPrice: (json['acquisitionPrice'] as num).toDouble(),
    );
  }
}

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
  final List<String> _defaultCodes = const ['^DJI', '998407.O', 'USDJPY=FX'];
  List<PortfolioItem> _portfolioItems = [];
  List<FinancialData> _defaultFinancialData = [];
  List<PortfolioDisplayData> _portfolioDisplayData = [];
  String _statusMessage = '';
  String _rawResponse = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _portfolioItems = List.from(initialPortfolioItems);
    _callWorker();
    _setupTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // --- Timer Setup ---
  Future<void> _setupTimer() async {
    _timer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    final updateInterval = prefs.getInt(updateIntervalKey) ?? 60;
    if (updateInterval > 0) {
      _timer = Timer.periodic(Duration(seconds: updateInterval), (Timer t) => _callWorker());
    }
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
      await Future.delayed(const Duration(milliseconds: 100));
      await _callWorker();
    }
  }

  Future<void> _editStock(int index, int newQuantity, double newAcquisitionPrice) async {
    if (newQuantity > 0 && newAcquisitionPrice >= 0) {
      setState(() {
        final originalItem = _portfolioItems[index];
        _portfolioItems[index] = PortfolioItem(
          code: originalItem.code,
          quantity: newQuantity,
          acquisitionPrice: newAcquisitionPrice,
        );
      });
      await _savePortfolio();
      await Future.delayed(const Duration(milliseconds: 100));
      await _callWorker();
    }
  }

  Future<void> _removeStock(int index) async {
    setState(() {
      _portfolioItems.removeAt(index);
    });
    await _savePortfolio();
    await Future.delayed(const Duration(milliseconds: 100));
    await _callWorker();
  }

  void _showRemoveStockConfirmDialog(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to remove this stock from your portfolio?\nこの株をポートフォリオから削除してもいいですか？'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(); // ダイアログを閉じる
              },
            ),
            TextButton(
              child: const Text('Remove'),
              onPressed: () {
                Navigator.of(context).pop(); // ダイアログを閉じる
                _removeStock(index); // 削除を実行
              },
            ),
          ],
        );
      },
    );
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
          Builder( // Builderを追加してPopoverのcontextを正しく取得
            builder: (context) => IconButton(
              icon: const Icon(Icons.timer_outlined),
              onPressed: () {
                showPopover(
                  context: context,
                  bodyBuilder: (context) => const UpdateIntervalPicker(),
                  onPop: () => _setupTimer(), // Popoverが閉じたらタイマーを再設定
                  direction: PopoverDirection.bottom,
                  width: 250,
                  arrowHeight: 15,
                  arrowWidth: 30,
                );
              },
              tooltip: 'Set Update Interval',
            ),
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
          if (_defaultFinancialData.isNotEmpty)
            _buildSectionHeader(context, 'Default Market Data'),
          if (_defaultFinancialData.isNotEmpty)
            _buildGridView(_defaultFinancialData, false, true),

          if (_portfolioDisplayData.isNotEmpty)
            _buildTotalProfitLoss(),

          _buildSectionHeader(context, 'My Portfolio'),
          if (_portfolioDisplayData.isNotEmpty)
            _buildPortfolioGridView(_portfolioDisplayData, true, false)
          else if (_portfolioItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Center(child: Text('Your portfolio is empty. Add stocks using the  +(Pulse) button.')),
            ),

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

  Map<String, double> _calculateTotalPortfolioMetrics() {
    double totalAcquisitionCost = 0;
    double totalEstimatedValue = 0;

    for (final item in _portfolioDisplayData) {
      final currentValueNum = double.tryParse(item.financialData.currentValue.replaceAll(',', ''));
      if (currentValueNum != null) {
        totalAcquisitionCost += item.portfolioItem.acquisitionPrice * item.portfolioItem.quantity;
        totalEstimatedValue += currentValueNum * item.portfolioItem.quantity;
      }
    }

    final totalProfitLoss = totalEstimatedValue - totalAcquisitionCost;
    return {'totalEstimatedValue': totalEstimatedValue, 'totalProfitLoss': totalProfitLoss,};
  }

  Widget _buildTotalProfitLoss() {
    final metrics = _calculateTotalPortfolioMetrics();
    final totalEstimatedValue = metrics['totalEstimatedValue']!;
    final totalProfitLoss = metrics['totalProfitLoss']!;
    final profitLossColor = totalProfitLoss >= 0 ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Total Portfolio Value',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '¥${totalEstimatedValue.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Total P/L: ',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '¥${totalProfitLoss.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: profitLossColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridView(List<FinancialData> data, bool showRemoveButton, bool isDefaultSection) {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: isDefaultSection
          ? const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.0 / 0.35, // 0.5 * 0.7
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            )
          : const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420,
              childAspectRatio: 4 / 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
      itemCount: data.length,
      itemBuilder: (context, index) {
        final item = data[index];
        return StockCard(
          financialData: item,
          onRemove: showRemoveButton ? () => _removeStock(index) : null,
          padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 8.0, bottom: 8.0),
        );
      },
    );
  }

  Widget _buildPortfolioGridView(List<PortfolioDisplayData> data, bool showButtons, bool isDefaultSection) {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: isDefaultSection
          ? const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.0 / 1.0,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            )
          : const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 250,
              childAspectRatio: 1.0 / 1.2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
      itemCount: data.length,
      itemBuilder: (context, index) {
        final item = data[index];
        return StockCard(
          financialData: item.financialData,
          portfolioItem: item.portfolioItem,
          onEdit: showButtons ? () => _showEditStockDialog(index) : null,
          onRemove: showButtons ? () => _showRemoveStockConfirmDialog(index) : null,
          padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 32.0, bottom: 8.0),
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

  void _showEditStockDialog(int index) {
    final currentItem = _portfolioItems[index];
    final quantityController = TextEditingController(text: currentItem.quantity.toString());
    final priceController = TextEditingController(text: currentItem.acquisitionPrice.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${currentItem.code}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantityController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Acquisition Price'),
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
              final quantity = int.tryParse(quantityController.text) ?? 0;
              final price = double.tryParse(priceController.text) ?? 0.0;
              _editStock(index, quantity, price);
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// --- Popover Widget for Settings ---
class UpdateIntervalPicker extends StatefulWidget {
  const UpdateIntervalPicker({super.key});

  @override
  State<UpdateIntervalPicker> createState() => _UpdateIntervalPickerState();
}

class _UpdateIntervalPickerState extends State<UpdateIntervalPicker> {
  int _updateInterval = 60;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _updateInterval = prefs.getInt(updateIntervalKey) ?? 60;
    });
  }

  Future<void> _setUpdateInterval(int? value) async {
    if (value == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(updateIntervalKey, value);
    setState(() {
      _updateInterval = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Update Interval', style: TextStyle(fontWeight: FontWeight.bold)),
          const Divider(),
          RadioListTile<int>(
            title: const Text('30 seconds'),
            value: 30,
            groupValue: _updateInterval,
            onChanged: _setUpdateInterval,
          ),
          RadioListTile<int>(
            title: const Text('1 minute'),
            value: 60,
            groupValue: _updateInterval,
            onChanged: _setUpdateInterval,
          ),
          RadioListTile<int>(
            title: const Text('5 minutes'),
            value: 300,
            groupValue: _updateInterval,
            onChanged: _setUpdateInterval,
          ),
          RadioListTile<int>(
            title: const Text('Manual Only'),
            value: 0,
            groupValue: _updateInterval,
            onChanged: _setUpdateInterval,
          ),
        ],
      ),
    );
  }
}

// --- Stock Card Widget ---
class StockCard extends StatelessWidget {
  final FinancialData financialData;
  final PortfolioItem? portfolioItem;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final EdgeInsetsGeometry? padding;

  const StockCard({
    super.key,
    required this.financialData,
    this.portfolioItem,
    this.onEdit,
    this.onRemove,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final changeColor = financialData.previousDayChange.startsWith('-') ? Colors.red : Colors.green;

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
            padding: padding ?? const EdgeInsets.only(left: 16.0, right: 16.0, top: 8.0, bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
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
          if (onEdit != null || onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: onEdit,
                      tooltip: 'Edit Portfolio Item',
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                  if (onRemove != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: onRemove,
                      tooltip: 'Remove from Portfolio',
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}