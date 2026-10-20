class Transaction {
  final String? id;
  final String userId;
  final double amount;
  final String categoryId;
  final String? merchantName;
  final String? merchantUen;
  final String? note;
  final String triggerType;
  final String? rawQr;
  final String? paymentMode;
  final DateTime createdAt;

  Transaction({
    this.id,
    required this.userId,
    required this.amount,
    required this.categoryId,
    this.merchantName,
    this.merchantUen,
    this.note,
    required this.triggerType,
    this.rawQr,
    this.paymentMode,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'user_id': userId,
    'amount': amount,
    'category_id': categoryId,
    if (merchantName != null) 'merchant_name': merchantName,
    if (merchantUen != null) 'merchant_uen': merchantUen,
    if (note != null) 'note': note,
    'trigger_type': triggerType,
    if (rawQr != null) 'raw_qr': rawQr,
    if (paymentMode != null) 'payment_mode': paymentMode,
    'created_at': createdAt.toIso8601String(),
  };

  factory Transaction.fromMap(Map<String, dynamic> m) => Transaction(
    id: m['id'],
    userId: m['user_id'],
    amount: (m['amount'] as num).toDouble(),
    categoryId: m['category_id'],
    merchantName: m['merchant_name'],
    merchantUen: m['merchant_uen'],
    note: m['note'],
    triggerType: m['trigger_type'],
    rawQr: m['raw_qr'],
    paymentMode: m['payment_mode'],
    createdAt: DateTime.parse(m['created_at']),
  );
}