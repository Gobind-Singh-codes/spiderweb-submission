import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StockScreen(),
    );
  }
}

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  Map<String, double> prices = {};
  Map<String, double> oldPrices = {};
  Set<String> anomalies = {};
  late WebSocket _socket;
  bool isConnecting = true;
  bool isConnected = false;
  int retryDelay = 2;
  final int maxDelay = 30;

  String get connectionStatus {
    if (isConnecting) return 'Connecting...';
    if (isConnected) return 'Connected';
    return 'Reconnecting...';
  }

  Color get connectionColor {
    if (isConnecting) return Colors.grey;
    if (isConnected) return Colors.green;
    return Colors.orange;
  }

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() async {
    setState(() {
      isConnecting = true;
      isConnected = false;
    });

    try {
      _socket = await WebSocket.connect('ws://127.0.0.1:5000/ws');

      setState(() {
        isConnecting = false;
        isConnected = true;
        retryDelay = 2;
      });

      _socket.listen(
        _onData,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
      );
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    setState(() {
      isConnected = false;
      isConnecting = false;
    });

    Future.delayed(Duration(seconds: retryDelay), _connect);
    retryDelay = (retryDelay * 2).clamp(2, maxDelay);
  }

  void _onData(dynamic data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is List) {
        for (var stock in decoded) {
          final ticker = stock['ticker'].toString();
          final newPrice = double.tryParse(stock['price'].toString());
          if (newPrice == null) continue;

          final oldPrice = prices[ticker];
          if (oldPrice != null) {
            final drop = (oldPrice - newPrice) / oldPrice;
            if (drop > 0.5) {
              anomalies.add(ticker);
              continue; // skip anomalous
            } else {
              anomalies.remove(ticker);
            }
          }

          oldPrices[ticker] = prices[ticker] ?? newPrice;
          prices[ticker] = newPrice;
        }

        setState(() {});
      }
    } catch (_) {
      // ignore malformed
    }
  }

  @override
  void dispose() {
    _socket.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sortedKeys = prices.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Stocks'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Chip(
              backgroundColor: connectionColor,
              label: Text(
                connectionStatus,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: sortedKeys.map((ticker) {
              final price = prices[ticker]!;
              final old = oldPrices[ticker] ?? price;
              final change = price - old;
              final color = change > 0
                  ? Colors.green
                  : change < 0
                  ? Colors.red
                  : Colors.black;
              final isAnomaly = anomalies.contains(ticker);

              return Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 20,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade100,
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          ticker,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isAnomaly)
                          const Padding(
                            padding: EdgeInsets.only(left: 4.0),
                            child: Icon(
                              Icons.warning,
                              color: Colors.orange,
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        '\$${price.toStringAsFixed(2)}',
                        key: ValueKey(price),
                        style: TextStyle(
                          fontSize: 16,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
