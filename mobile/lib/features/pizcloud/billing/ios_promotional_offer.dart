// mobile/lib/features/pizcloud/billing/ios_promotional_offer.dart

class IosPromotionalOffer {
  final String offerId;
  final String keyId;
  final String nonce;
  final int timestampMs;
  final String signature;

  const IosPromotionalOffer({
    required this.offerId,
    required this.keyId,
    required this.nonce,
    required this.timestampMs,
    required this.signature,
  });

  factory IosPromotionalOffer.fromJson(Map<String, dynamic> json) {
    return IosPromotionalOffer(
      offerId: (json['offerId'] ?? json['identifier'] ?? '') as String,
      keyId: (json['keyId'] ?? json['keyIdentifier'] ?? '') as String,
      nonce: (json['nonce'] ?? '') as String,
      timestampMs: (json['timestampMs'] ?? json['timestamp'] ?? 0) as int,
      signature: (json['signature'] ?? '') as String,
    );
  }

  bool get isValid =>
      offerId.isNotEmpty && keyId.isNotEmpty && nonce.isNotEmpty && signature.isNotEmpty && timestampMs > 0;
}
