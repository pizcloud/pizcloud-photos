import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/billing.provider.dart';

class UploadQuotaGuard {
  UploadQuotaGuard(this.ref);
  final Ref ref;

  Future<bool> ensureCanUpload({int? incomingBytes}) async {
    final usage = await ref.read(entitlementApiClientProvider).getUsage();
    if ((usage['state'] as String?) == 'blocked') return false;

    if (incomingBytes != null) {
      final limitGb = (usage['limit_gb'] as num).toDouble();
      final usedGb = (usage['used_gb'] as num).toDouble();
      final incGb = (incomingBytes / (1024 * 1024 * 1024));
      if (usedGb + incGb > limitGb) return false;
    }
    return true;
  }
}
