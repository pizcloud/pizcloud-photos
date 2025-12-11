// mobile/lib/models/pizcloud/referral_withdrawal.model.dart

class ReferralWithdrawal {
  final String id;
  final String email;
  final double amount;
  final String currency;
  final String status; // 'pending' | 'approved' | 'rejected' | 'paid'
  final String method; // 'bank' | 'paypal'
  final String? note;
  final String? adminNote;

  final String? bankName;
  final String? bankAccountNumber;
  final String? bankAccountHolderName;

  final String? paypalEmail;
  final String? paypalFullName;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? processedAt;

  const ReferralWithdrawal({
    required this.id,
    required this.email,
    required this.amount,
    required this.currency,
    required this.status,
    required this.method,
    this.note,
    this.adminNote,
    this.bankName,
    this.bankAccountNumber,
    this.bankAccountHolderName,
    this.paypalEmail,
    this.paypalFullName,
    this.createdAt,
    this.updatedAt,
    this.processedAt,
  });

  factory ReferralWithdrawal.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is String && v.isNotEmpty) {
        try {
          return DateTime.parse(v);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    return ReferralWithdrawal(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: (json['currency'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      method: (json['method'] ?? '').toString(),
      note: json['note'] as String?,
      adminNote: json['adminNote'] as String?,
      bankName: json['bankName'] as String?,
      bankAccountNumber: json['bankAccountNumber'] as String?,
      bankAccountHolderName: json['bankAccountHolderName'] as String?,
      paypalEmail: json['paypalEmail'] as String?,
      paypalFullName: json['paypalFullName'] as String?,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      processedAt: parseDate(json['processedAt']),
    );
  }
}

class ReferralWithdrawalListResponse {
  final List<ReferralWithdrawal> items;
  final int page;
  final int limit;
  final int total;

  const ReferralWithdrawalListResponse({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
  });

  factory ReferralWithdrawalListResponse.empty() =>
      const ReferralWithdrawalListResponse(items: [], page: 1, limit: 20, total: 0);
}
