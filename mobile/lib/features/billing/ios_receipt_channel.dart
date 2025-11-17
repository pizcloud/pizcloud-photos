import 'package:flutter/services.dart';

class IosReceiptChannel {
  static const _ch = MethodChannel('com.yourbrand.iap/receipt');

  static Future<String> getReceiptBase64() async {
    final s = await _ch.invokeMethod<String>('getAppStoreReceiptBase64');
    if (s == null || s.isEmpty) throw Exception('No App Store receipt found');
    return s;
  }
}
