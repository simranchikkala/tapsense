class QrParseResult {
  final String? merchantName;
  final String? merchantUen;
  final double? amount;
  final String? proxyValue; // PayNow phone/UEN
  final bool isPayNow;
  final bool isSGQR;
  final String raw;

  QrParseResult({
    this.merchantName,
    this.merchantUen,
    this.amount,
    this.proxyValue,
    required this.isPayNow,
    required this.isSGQR,
    required this.raw,
  });
}

class QrParser {
  /// Parse an EMVCo/SGQR QR string into structured data.
  static QrParseResult parse(String raw) {
    final tags = _parseTlv(raw);

    // Tag 26–51: Merchant account info blocks
    // PayNow sits in tag 26, SGQR in various slots
    String? merchantName  = tags['59'];   // EMVCo tag 59
    String? merchantUen;
    String? proxyValue;
    double? amount;
    bool isPayNow = false;
    bool isSGQR   = false;

    // Amount — tag 54
    final amountStr = tags['54'];
    if (amountStr != null) {
      amount = double.tryParse(amountStr);
    }

    // Merchant name — tag 59
    merchantName = tags['59'];

    // Walk merchant account blocks 26–51
    for (int i = 26; i <= 51; i++) {
      final block = tags[i.toString().padLeft(2, '0')];
      if (block == null) continue;
      final sub = _parseTlv(block);

      // GUID tag 00 identifies the scheme
      final guid = sub['00'] ?? '';

      if (guid.contains('SG.PAYNOW') || guid.contains('paynow')) {
        isPayNow = true;
        proxyValue = sub['01']; // phone or UEN
        merchantUen = sub['01'];
      }

      if (guid.contains('SG.COM') || guid.contains('com.sg') ||
          block.contains('SG.SGQR')) {
        isSGQR = true;
      }

      // Some SGQR blocks carry merchant name in sub-tag 02
      if (merchantName == null && sub['02'] != null) {
        merchantName = sub['02'];
      }
    }

    return QrParseResult(
      merchantName: merchantName,
      merchantUen: merchantUen,
      amount: amount,
      proxyValue: proxyValue,
      isPayNow: isPayNow,
      isSGQR: isSGQR,
      raw: raw,
    );
  }

  /// Parse EMVCo TLV: each field is TTLLVV...
  /// TT = 2-char tag, LL = 2-char length (decimal), VV = value
  static Map<String, String> _parseTlv(String data) {
    final result = <String, String>{};
    int i = 0;
    while (i + 4 <= data.length) {
      final tag = data.substring(i, i + 2);
      final lenStr = data.substring(i + 2, i + 4);
      final len = int.tryParse(lenStr);
      if (len == null) break;
      if (i + 4 + len > data.length) break;
      final value = data.substring(i + 4, i + 4 + len);
      result[tag] = value;
      i += 4 + len;
    }
    return result;
  }
}