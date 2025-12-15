class ReferralPayoutMethod {
  final String? method; // 'bank' | 'paypal' | null
  final String? bankName;
  final String? bankAccountNumber;
  final String? bankAccountHolderName;
  final String? paypalEmail;
  final String? paypalFullName;

  const ReferralPayoutMethod({
    required this.method,
    this.bankName,
    this.bankAccountNumber,
    this.bankAccountHolderName,
    this.paypalEmail,
    this.paypalFullName,
  });

  factory ReferralPayoutMethod.fromJson(Map<String, dynamic> json) {
    return ReferralPayoutMethod(
      method: json['method'] as String?,
      bankName: json['bankName'] as String?,
      bankAccountNumber: json['bankAccountNumber'] as String?,
      bankAccountHolderName: json['bankAccountHolderName'] as String?,
      paypalEmail: json['paypalEmail'] as String?,
      paypalFullName: json['paypalFullName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'method': method,
      'bankName': bankName,
      'bankAccountNumber': bankAccountNumber,
      'bankAccountHolderName': bankAccountHolderName,
      'paypalEmail': paypalEmail,
      'paypalFullName': paypalFullName,
    };
  }
}
