import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:immich_mobile/models/pizcloud/referral_payout_method.model.dart';
import 'package:immich_mobile/services/pizcloud/referral_payout_method.service.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as pizPersist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';

class MonthlyStat {
  final String month;
  final double commission;
  final int activeUsers;

  const MonthlyStat({required this.month, required this.commission, required this.activeUsers});
}

class ReferrerInfo {
  final String email;
  final String? referralCode;
  final String? discountStartAt;
  final String? discountEndAt;

  const ReferrerInfo({required this.email, this.referralCode, this.discountStartAt, this.discountEndAt});
}

String formatMonth(String month) {
  final parts = month.split('-');
  if (parts.length != 2) return month;
  final year = parts[0];
  final m = parts[1].padLeft(2, '0');
  return '$m/$year';
}

String formatCurrency(num amount, String currencyCode) {
  if (amount.isNaN || amount.isInfinite) {
    return '0';
  }

  try {
    final formatter = NumberFormat.currency(locale: 'vi_VN', name: currencyCode);
    return formatter.format(amount);
  } catch (_) {
    final formatter = NumberFormat.decimalPattern('vi_VN');
    return '${formatter.format(amount)} $currencyCode';
  }
}

String formatDate(String? isoString) {
  if (isoString == null || isoString.isEmpty) return '';
  try {
    final d = DateTime.parse(isoString);
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    return '$day/$month/$year';
  } catch (_) {
    return isoString;
  }
}

@RoutePage()
class DiscountCodePage extends HookConsumerWidget {
  const DiscountCodePage({super.key, this.userEmail});
  final String? userEmail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Data from backend
    final referralCode = useState<String>('');
    final totalReferredUsers = useState<int>(0);
    final totalCommission = useState<double>(0);
    final monthlyStatsState = useState<List<MonthlyStat>>(<MonthlyStat>[]);
    final currency = useState<String>('USD');
    final localReferrer = useState<ReferrerInfo?>(null);

    final totalCommissionPaid = useState<double>(0);
    final availableBalance = useState<double>(0);
    final totalRequestedWithdrawal = useState<double>(0);
    final totalPaidWithdrawal = useState<double>(0);
    final pendingWithdrawalAmount = useState<double>(0);

    // Loading + error cho summary
    final summaryLoading = useState<bool>(true);
    final summaryError = useState<String?>(null);

    // Apply-referrer input
    final applyCodeController = useTextEditingController();
    final applyLoading = useState<bool>(false);
    final applyError = useState<String?>(null);
    final applySuccess = useState<String?>(null);

    final payoutMethodState = useState<ReferralPayoutMethod?>(null);

    // final pizPersistApiFuture = pizPersist.ApiPersistCookieJarService.instance(baseUrl: pizCloudServerUrl);
    final pizPersistApiFuture = useMemoized(() async {
      final baseUrl = await PizcloudBaseUrlService().resolveBaseUrl();
      return pizPersist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
    });

    Future<void> loadSummary() async {
      summaryLoading.value = true;
      summaryError.value = null;

      try {
        // New Dio-based implementation using PersistCookieJar (sid) + headers
        final api = await pizPersistApiFuture;
        final res = await api.client.get<dynamic>('/referral/summary');
        final status = res.statusCode ?? 0;
        if (status < 200 || status >= 300) {
          String? messageCode;
          try {
            final body = res.data;
            if (body is Map<String, dynamic>) {
              final msg = body['message'];
              if (msg is String) {
                messageCode = msg;
              } else if (msg is List && msg.isNotEmpty && msg.first is String) {
                messageCode = msg.first as String;
              }
            }
          } catch (_) {}

          if (messageCode == 'EMAIL_REQUIRED' || messageCode == 'USER_NOT_FOUND') {
            summaryError.value = 'referral.apply_missing_email'.tr();
          } else {
            summaryError.value = 'referral.apply_unknown_error'.tr();
          }
          return;
        }

        final data = res.data;
        if (data is! Map<String, dynamic>) {
          summaryError.value = 'referral.apply_unknown_error'.tr();
          return;
        }

        referralCode.value = (data['referralCode'] ?? '').toString();
        totalReferredUsers.value = (data['totalReferredUsers'] as num?)?.toInt() ?? 0;
        totalCommission.value = (data['totalCommission'] as num?)?.toDouble() ?? 0.0;
        currency.value = (data['currency'] ?? 'USD').toString();

        totalCommissionPaid.value = (data['totalCommissionPaid'] as num?)?.toDouble() ?? 0.0;
        availableBalance.value = (data['availableBalance'] as num?)?.toDouble() ?? 0.0;
        totalRequestedWithdrawal.value = (data['totalRequestedWithdrawal'] as num?)?.toDouble() ?? 0.0;
        totalPaidWithdrawal.value = (data['totalPaidWithdrawal'] as num?)?.toDouble() ?? 0.0;
        pendingWithdrawalAmount.value = (data['pendingWithdrawalAmount'] as num?)?.toDouble() ?? 0.0;

        final statsRaw = data['monthlyStats'] as List<dynamic>? ?? <dynamic>[];
        monthlyStatsState.value = statsRaw
            .whereType<Map<String, dynamic>>()
            .map(
              (m) => MonthlyStat(
                month: (m['month'] ?? '').toString(),
                commission: (m['commission'] as num?)?.toDouble() ?? 0.0,
                activeUsers: (m['activeUsers'] as num?)?.toInt() ?? 0,
              ),
            )
            .toList();

        final refRaw = data['referrer'];
        if (refRaw is Map<String, dynamic>) {
          localReferrer.value = ReferrerInfo(
            email: (refRaw['email'] ?? '').toString(),
            referralCode: refRaw['referralCode']?.toString(),
            discountStartAt: refRaw['discountStartAt']?.toString(),
            discountEndAt: refRaw['discountEndAt']?.toString(),
          );
        } else {
          localReferrer.value = null;
        }
      } catch (e, s) {
        debugPrint('Error loading referral summary: $e\n$s');
        summaryError.value = 'referral.apply_unknown_error'.tr();
      } finally {
        summaryLoading.value = false;
      }
    }

    Future<void> loadPayoutMethod() async {
      if (userEmail == null || userEmail!.isEmpty) {
        payoutMethodState.value = null;
        return;
      }

      try {
        final pm = await referralPayoutMethodService.loadPayoutMethod(userEmail!);
        payoutMethodState.value = pm;
      } catch (e, s) {
        debugPrint('Error loading payout method: $e\n$s');
      }
    }

    useEffect(() {
      loadSummary();
      loadPayoutMethod();
      return null;
    }, [userEmail]);

    Future<void> handleApplyReferrer() async {
      applyError.value = null;
      applySuccess.value = null;

      final code = applyCodeController.text.trim();

      if (code.isEmpty) {
        applyError.value = 'referral.apply_empty_error'.tr();
        return;
      }

      if (userEmail == null || userEmail!.isEmpty) {
        applyError.value = 'referral.apply_missing_email'.tr();
        return;
      }

      applyLoading.value = true;

      try {
        // New Dio-based implementation using PersistCookieJar (sid) + headers
        final api = await pizPersistApiFuture;
        final res = await api.client.post<dynamic>('/referral/apply-code', data: {'email': userEmail, 'code': code});

        final status = res.statusCode ?? 0;
        if (status < 200 || status >= 300) {
          debugPrint('Failed to apply referral code: $status ${res.data}');
          applyError.value = 'referral.apply_unknown_error'.tr();
          return;
        }

        final dynamic body = res.data;
        if (body is! Map<String, dynamic>) {
          applyError.value = 'referral.apply_unknown_error'.tr();
          return;
        }

        final success = body['success'] == true;
        if (!success) {
          final reason = (body['reason'] ?? '').toString().toUpperCase();

          switch (reason) {
            case 'NOT_FOUND':
              applyError.value = 'referral.apply_not_found'.tr();
              break;
            case 'OWN_CODE':
              applyError.value = 'referral.apply_own_code'.tr();
              break;
            case 'ALREADY_HAS_REFERRER':
              applyError.value = 'referral.apply_already_has_referrer'.tr();
              break;
            case 'EMPTY_CODE':
              applyError.value = 'referral.apply_empty_error'.tr();
              break;
            case 'USER_NOT_FOUND':
            case 'EMAIL_REQUIRED':
              applyError.value = 'referral.apply_missing_email'.tr();
              break;
            default:
              applyError.value = 'referral.apply_unknown_error'.tr();
          }
          return;
        }

        final refData = body['referrer'];
        if (refData is Map<String, dynamic>) {
          final info = ReferrerInfo(
            email: (refData['email'] ?? '').toString(),
            referralCode: refData['referralCode']?.toString(),
            discountStartAt: refData['discountStartAt']?.toString(),
            discountEndAt: refData['discountEndAt']?.toString(),
          );

          localReferrer.value = info;
          applyCodeController.clear();
          applySuccess.value = 'referral.apply_success'.tr(namedArgs: {'email': info.email});
        } else {
          applyError.value = 'referral.apply_unknown_error'.tr();
        }
      } catch (e, s) {
        debugPrint('Error applying referral code: $e\n$s');
        applyError.value = 'referral.apply_unknown_error'.tr();
      } finally {
        applyLoading.value = false;
      }
    }

    Widget buildLoadedBody() {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // Referrer section
            _ReferrerSection(
              localReferrer: localReferrer.value,
              applyCodeController: applyCodeController,
              applyLoading: applyLoading.value,
              applyError: applyError.value,
              applySuccess: applySuccess.value,
              onApply: handleApplyReferrer,
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('referral.discount_code'.tr())),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (summaryLoading.value) {
              return const Center(child: CircularProgressIndicator());
            }

            if (summaryError.value != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(summaryError.value!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 12),
                      _PillButton(label: 'retry'.tr(), onPressed: loadSummary, primary: true),
                    ],
                  ),
                ),
              );
            }

            return buildLoadedBody();
          },
        ),
      ),
    );
  }
}

// ----------------------
// Child widgets
// ----------------------
class _ReferrerSection extends StatelessWidget {
  const _ReferrerSection({
    required this.localReferrer,
    required this.applyCodeController,
    required this.applyLoading,
    required this.applyError,
    required this.applySuccess,
    required this.onApply,
  });

  final ReferrerInfo? localReferrer;
  final TextEditingController applyCodeController;
  final bool applyLoading;
  final String? applyError;
  final String? applySuccess;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.dividerColor.withValues(alpha: 0.4);

    if (localReferrer != null) {
      final info = localReferrer!;
      final hasDiscountRange = (info.discountStartAt ?? '').isNotEmpty && (info.discountEndAt ?? '').isNotEmpty;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'referral.your_discount_code'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'referral.referrer_label'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(width: 4),
                Text(info.email, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
            if (info.referralCode != null && info.referralCode!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'referral.discount_code'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(info.referralCode!, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
            if (hasDiscountRange) ...[
              const SizedBox(height: 4),
              Text(
                'referral.referrer_discount_range'.tr(
                  namedArgs: {'start': formatDate(info.discountStartAt), 'end': formatDate(info.discountEndAt)},
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dividerColor, style: BorderStyle.solid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'referral.input_discount_code'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'referral.referrer_hint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: applyCodeController,
                  decoration: InputDecoration(
                    hintText: 'referral.apply_referrer_placeholder'.tr(),
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: dividerColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onApply(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: _PillButton(
                  label: applyLoading ? 'referral.apply_loading'.tr() : 'referral.apply_referrer_button'.tr(),
                  onPressed: onApply,
                  primary: true,
                  isBusy: applyLoading,
                ),
              ),
            ],
          ),
          if (applyError != null && applyError!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(applyError!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.red.shade500)),
          ] else if (applySuccess != null && applySuccess!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(applySuccess!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade600)),
          ],
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onPressed, this.primary = true, this.isBusy = false});

  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final backgroundColor = primary ? colorScheme.primary : Colors.transparent;
    final foregroundColor = primary ? colorScheme.onPrimary : colorScheme.primary;
    final borderColor = colorScheme.primary;

    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: isBusy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: const StadiumBorder(),
          side: BorderSide(color: borderColor, width: 1),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
        child: isBusy
            ? SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                ),
              )
            : Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: primary ? colorScheme.onPrimary : colorScheme.primary,
                ),
              ),
      ),
    );
  }
}
