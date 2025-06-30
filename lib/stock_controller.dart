import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class StockController extends ChangeNotifier {
  final Map<String, double> _stockPrices = {};
  WebSocket? _socket;

  bool isConnected = false;
  bool isConnecting = true;

  Map<String, String> get stockMap =>
      _stockPrices.map((key, value) => MapEntry(key, value.toStringAsFixed(2)));

  void connect() async {
    isConnecting = true;
    notifyListeners();

    try {
      _socket = await WebSocket.connect('ws://127.0.0.1:5000/ws');
      isConnected = true;
      isConnecting = false;
      notifyListeners();

      _socket!.listen(
        (data) {
          try {
            final decoded = jsonDecode(data);

            if (decoded is List) {
              bool updated = false;

              for (var stock in decoded) {
                if (stock is Map<String, dynamic> &&
                    stock.containsKey('ticker') &&
                    stock.containsKey('price')) {
                  final ticker = stock['ticker'].toString();
                  final newPrice = double.tryParse(stock['price'].toString());

                  if (newPrice == null) continue;

                  // Anomaly check: if previous exists and price drops by >50%
                  if (_stockPrices.containsKey(ticker)) {
                    final oldPrice = _stockPrices[ticker]!;
                    final percentDrop = (oldPrice - newPrice) / oldPrice;

                    if (percentDrop > 0.5) {
                      // Skip anomalous drop
                      continue;
                    }
                  }

                  if (_stockPrices[ticker] != newPrice) {
                    _stockPrices[ticker] = newPrice;
                    updated = true;
                  }
                }
              }

              if (updated) {
                notifyListeners();
              }
            }
          } catch (_) {
            // ignore malformed data silently
          }
        },
        onDone: () {
          isConnected = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 2), connect);
        },
        onError: (_) {
          isConnected = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 2), connect);
        },
      );
    } catch (_) {
      isConnected = false;
      isConnecting = false;
      notifyListeners();
      Future.delayed(const Duration(seconds: 2), connect);
    }
  }

  void disposeController() {
    _socket?.close();
    _stockPrices.clear();
  }
}
