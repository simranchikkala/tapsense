class Transaction {
  final String? id;
  final String userId;
  final double amount;       // negative = spend/debit, positive = credit/income
  final String categoryId;
  final String? merchantName;
  final String? merchantUen;
  final String? note;
  final String triggerType;
  final String? rawQr;
  final String? paymentMode;
  final String txType;       // 'debit' | 'credit'
  final String? sharedWith;  // 'you_owe' | 'they_owe' | null
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
    this.txType = 'debit',
    this.sharedWith,
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
    'tx_type': txType,
    if (sharedWith != null) 'shared_with': sharedWith,
    'created_at': createdAt.toIso8601String(),
  };

  factory Transaction.fromMap(Map<String, dynamic> m) => Transaction(
    id: m['id'],
    userId: m['user_id'],
    amount: (m['amount'] as num).toDouble(),
    categoryId: m['category_id'] ?? 'other',
    merchantName: m['merchant_name'],
    merchantUen: m['merchant_uen'],
    note: m['note'],
    triggerType: m['trigger_type'] ?? 'manual',
    rawQr: m['raw_qr'],
    paymentMode: m['payment_mode'],
    txType: m['tx_type'] ?? 'debit',
    sharedWith: m['shared_with'],
    createdAt: DateTime.parse(m['created_at']),
  );
}