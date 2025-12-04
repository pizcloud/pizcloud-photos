import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
// import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:immich_mobile/config/app_config.dart';

final String pizCloudServerUrl = AppConfig.pizCloudServerUrl.trim();

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
class ReferralPage extends HookConsumerWidget {
  const ReferralPage({super.key, this.userEmail});
  final String? userEmail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // --- UI states ---
    final copyMessage = useState<String?>(null);
    final shareMessage = useState<String?>(null);

    // Data from backend
    final referralCode = useState<String>('');
    final totalReferredUsers = useState<int>(0);
    final totalCommission = useState<double>(0);
    final monthlyStatsState = useState<List<MonthlyStat>>(<MonthlyStat>[]);
    final currency = useState<String>('VND');
    final localReferrer = useState<ReferrerInfo?>(null);

    // Loading + error cho summary
    final summaryLoading = useState<bool>(true);
    final summaryError = useState<String?>(null);

    // Apply-referrer input
    final applyCodeController = useTextEditingController();
    final applyLoading = useState<bool>(false);
    final applyError = useState<String?>(null);
    final applySuccess = useState<String?>(null);

    Future<void> loadSummary() async {
      summaryLoading.value = true;
      summaryError.value = null;

      try {
        // final rawBase = AppConfig.serverBaseUrl.trim();
        // if (rawBase.isEmpty) {
        //   summaryError.value = 'referral.apply_unknown_error'.tr();
        //   return;
        // }
        final base = pizCloudServerUrl.replaceAll(RegExp(r'/+$'), '');

        Uri uri = Uri.parse('$base/papi/referral/summary');
        if (userEmail != null && userEmail!.isNotEmpty) {
          uri = uri.replace(queryParameters: {'email': userEmail!});
        }

        final res = await http.get(uri);

        if (res.statusCode < 200 || res.statusCode >= 300) {
          String? messageCode;
          try {
            final body = jsonDecode(res.body);
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

        final data = jsonDecode(res.body);
        if (data is! Map<String, dynamic>) {
          summaryError.value = 'referral.apply_unknown_error'.tr();
          return;
        }

        referralCode.value = (data['referralCode'] ?? '').toString();
        totalReferredUsers.value = (data['totalReferredUsers'] as num?)?.toInt() ?? 0;
        totalCommission.value = (data['totalCommission'] as num?)?.toDouble() ?? 0.0;
        currency.value = (data['currency'] ?? 'VND').toString();

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

    useEffect(() {
      loadSummary();
      return null;
    }, [userEmail]);

    Future<void> handleCopy() async {
      copyMessage.value = null;
      shareMessage.value = null;

      try {
        final code = referralCode.value.trim();
        if (code.isEmpty) {
          copyMessage.value = 'referral.copy_error'.tr();
          return;
        }
        await Clipboard.setData(ClipboardData(text: code));
        copyMessage.value = 'referral.copy_success'.tr();
      } catch (e) {
        debugPrint('Error copying referral code: $e');
        copyMessage.value = 'referral.copy_error'.tr();
      }
    }

    Future<void> handleShare() async {
      copyMessage.value = null;
      shareMessage.value = null;

      final code = referralCode.value.trim();
      if (code.isEmpty) {
        shareMessage.value = 'referral.share_error'.tr();
        return;
      }

      final text = '${'referral.share_text_prefix'.tr()} $code';

      try {
        await Share.share(text);
      } catch (e) {
        debugPrint('Error sharing referral code: $e');
        // fallback: copy clipboard
        try {
          await Clipboard.setData(ClipboardData(text: text));
          shareMessage.value = 'referral.share_fallback'.tr();
        } catch (err) {
          debugPrint('Error share fallback: $err');
          shareMessage.value = 'referral.share_fallback_error'.tr();
        }
      }
    }

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
        // final rawBase = AppConfig.serverBaseUrl.trim();
        // if (rawBase.isEmpty) {
        //   applyError.value = 'referral.apply_unknown_error'.tr();
        //   return;
        // }
        final base = pizCloudServerUrl.replaceAll(RegExp(r'/+$'), '');

        final uri = Uri.parse('$base/papi/referral/apply-code');

        final res = await http.post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': userEmail, 'code': code}),
        );

        if (res.statusCode < 200 || res.statusCode >= 300) {
          debugPrint('Failed to apply referral code: ${res.statusCode} ${res.body}');
          applyError.value = 'referral.apply_unknown_error'.tr();
          return;
        }

        final dynamic body = jsonDecode(res.body);
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

    final isEmptyState =
        !summaryLoading.value &&
        summaryError.value == null &&
        totalReferredUsers.value == 0 &&
        totalCommission.value == 0 &&
        monthlyStatsState.value.isEmpty;

    Widget buildLoadedBody() {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text('referral.title'.tr(), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'referral.subtitle'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 16),

            // Referral code card
            _ReferralCodeCard(
              referralCode: referralCode.value.isEmpty ? '--------' : referralCode.value,
              copyMessage: copyMessage.value,
              shareMessage: shareMessage.value,
              onCopy: handleCopy,
              onShare: handleShare,
            ),
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

            // Summary stats
            _SummaryStats(
              totalReferredUsers: totalReferredUsers.value,
              totalCommission: totalCommission.value,
              currency: currency.value,
            ),

            if (isEmptyState) ...[const SizedBox(height: 16), _EmptyState(onCopy: handleCopy)],

            if (monthlyStatsState.value.isNotEmpty) ...[
              const SizedBox(height: 24),
              _MonthlyStatsTable(stats: monthlyStatsState.value, currency: currency.value),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('referral.title'.tr())),
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

class _ReferralCodeCard extends StatelessWidget {
  const _ReferralCodeCard({
    required this.referralCode,
    required this.copyMessage,
    required this.shareMessage,
    required this.onCopy,
    required this.onShare,
  });

  final String referralCode;
  final String? copyMessage;
  final String? shareMessage;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final dividerColor = theme.dividerColor.withValues(alpha: 0.4);

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
            'referral.code_label'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: theme.colorScheme.surfaceContainerHighest,
                    border: Border.all(color: dividerColor),
                  ),
                  child: SelectableText(
                    referralCode,
                    style: theme.textTheme.titleMedium?.copyWith(
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PillButton(label: 'referral.copy_code'.tr(), onPressed: onCopy, primary: true),
                  const SizedBox(height: 8),
                  _PillButton(label: 'referral.share'.tr(), onPressed: onShare, primary: false),
                ],
              ),
            ],
          ),
          if (copyMessage != null && copyMessage!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(copyMessage!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade600)),
          ],
          if (shareMessage != null && shareMessage!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(shareMessage!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
          ],
        ],
      ),
    );
  }
}

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
              'referral.referrer_applied_title'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(info.email, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            if (info.referralCode != null && info.referralCode!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'referral.referrer_code'.tr(),
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
            'referral.referrer_label'.tr(),
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

class _SummaryStats extends StatelessWidget {
  const _SummaryStats({required this.totalReferredUsers, required this.totalCommission, required this.currency});

  final int totalReferredUsers;
  final double totalCommission;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(label: 'referral.total_users'.tr(), value: totalReferredUsers.toString()),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(label: 'referral.total_commission'.tr(), value: formatCurrency(totalCommission, currency)),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.dividerColor.withValues(alpha: 0.4);

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
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCopy});

  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.dividerColor.withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dividerColor, style: BorderStyle.solid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('referral.empty_title'.tr(), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'referral.empty_text'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          _PillButton(label: 'referral.empty_cta'.tr(), onPressed: onCopy, primary: true),
        ],
      ),
    );
  }
}

class _MonthlyStatsTable extends StatelessWidget {
  const _MonthlyStatsTable({required this.stats, required this.currency});

  final List<MonthlyStat> stats;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.dividerColor.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('referral.table_title'.tr(), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dividerColor),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll<Color?>(theme.colorScheme.surfaceContainerHighest),
              columns: [
                DataColumn(
                  label: Text(
                    'referral.table_month'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'referral.table_commission'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'referral.table_active_users'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
              rows: stats
                  .map(
                    (s) => DataRow(
                      cells: [
                        DataCell(Text(formatMonth(s.month))),
                        DataCell(Text(formatCurrency(s.commission, currency))),
                        DataCell(Text(s.activeUsers.toString())),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
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
