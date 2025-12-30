import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/pizcloud/shared_email.model.dart';
import 'package:immich_mobile/services/pizcloud/partner_share_email_api.service.dart';

final partnerSharedEmailsProvider = FutureProvider.autoDispose<List<SharedEmailDto>>((ref) async {
  return PartnerShareEmailApiService.getSharedEmails();
});
