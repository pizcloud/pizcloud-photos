import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/pages/settings/pizcloud/referral_payout_method_page.dart';
// import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:immich_mobile/config/app_config.dart';
import 'package:immich_mobile/models/pizcloud/referral_payout_method.model.dart';
import 'package:immich_mobile/services/pizcloud/referral_payout_method.service.dart';
import 'package:immich_mobile/pages/settings/pizcloud/referral_withdrawals_page.dart';
import 'package:immich_mobile/services/pizcloud/auth_header.service.dart';
import 'package:immich_mobile/services/pizcloud/api.service.dart' as pizApi;

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

    final minWithdrawAmount = AppConfig.minReferralWithdrawAmount;

    final payoutMethodState = useState<ReferralPayoutMethod?>(null);

    final authHeaders = const AuthHeaderService();
    final pizApiService = pizApi.ApiService(baseUrl: pizCloudServerUrl, headers: authHeaders.authJson());

    // Ensure sid cookie is restored after app restart before hitting APIs
    useEffect(() {
      Future.microtask(() => pizApi.ApiService.ensureSidCookie(pizCloudServerUrl));
      return null;
    }, []);

    Future<void> loadSummary() async {
      summaryLoading.value = true;
      summaryError.value = null;

      try {
        await pizApi.ApiService.ensureSidCookie(pizCloudServerUrl);

        // Old http-based implementation (kept for reference)
        // Uri uri = Uri.parse('$base/papi/referral/summary');
        // if (userEmail != null && userEmail!.isNotEmpty) {
        //   uri = uri.replace(queryParameters: {'email': userEmail!});
        // }
        // final jsonHeaders = authHeaders.authJson();
        // final res = await http.get(uri, headers: jsonHeaders);

        // New Dio-based implementation using shared CookieJar (sid) + headers
        final client = pizApiService.client;
        final res = await client.get<dynamic>('/papi/referral/summary');

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
        await pizApi.ApiService.ensureSidCookie(pizCloudServerUrl);

        // Old http-based implementation (kept for reference)
        // final base = pizCloudServerUrl.replaceAll(RegExp(r'/+$'), '');
        // final uri = Uri.parse('$base/papi/referral/apply-code');
        // final jsonHeaders = authHeaders.authJson();
        // final res = await http.post(uri, headers: jsonHeaders, body: jsonEncode({'email': userEmail, 'code': code}));
        // if (res.statusCode < 200 || res.statusCode >= 300) {
        //   debugPrint('Failed to apply referral code: ${res.statusCode} ${res.body}');
        //   applyError.value = 'referral.apply_unknown_error'.tr();
        //   return;
        // }
        // final dynamic body = jsonDecode(res.body);

        // New Dio-based implementation using shared CookieJar (sid) + headers
        final res = await pizApiService.client.post<dynamic>(
          '/papi/referral/apply-code',
          data: {'email': userEmail, 'code': code},
        );

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

    final isEmptyState =
        !summaryLoading.value &&
        summaryError.value == null &&
        totalReferredUsers.value == 0 &&
        totalCommission.value == 0 &&
        monthlyStatsState.value.isEmpty;

    Future<void> openWithdrawDialog() async {
      if (userEmail == null || userEmail!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('referral.withdraw_missing_email'.tr())));
        return;
      }

      final currentBalance = availableBalance.value;
      final currentCurrency = currency.value;
      final minAmount = minWithdrawAmount;
      final payout = payoutMethodState.value;

      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);

          final amountController = TextEditingController(
            text: currentBalance > 0 ? currentBalance.toStringAsFixed(2) : '',
          );

          String? errorText;
          bool submitting = false;
          String withdrawMethod = (payout?.method == 'paypal' ? 'paypal' : 'bank');

          void goEditPayout() {
            Navigator.of(ctx).pop();
            if (userEmail == null || userEmail!.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReferralPayoutMethodPage(
                  userEmail: userEmail!,
                  onSaved: () {
                    loadPayoutMethod();
                    loadSummary();
                  },
                ),
              ),
            );
          }

          bool hasInfoFor(String method) {
            if (payout == null) return false;
            if (method == 'bank') {
              return (payout.bankName ?? '').isNotEmpty &&
                  (payout.bankAccountNumber ?? '').isNotEmpty &&
                  (payout.bankAccountHolderName ?? '').isNotEmpty;
            } else {
              return (payout.paypalEmail ?? '').isNotEmpty;
            }
          }

          return StatefulBuilder(
            builder: (ctx, setState) {
              Future<void> submit() async {
                FocusScope.of(ctx).unfocus();

                final raw = amountController.text.trim().replaceAll(',', '');
                final amount = double.tryParse(raw);

                if (amount == null || amount <= 0) {
                  setState(() {
                    errorText = 'referral.withdraw_amount_invalid'.tr();
                  });
                  return;
                }

                if (amount < minAmount) {
                  setState(() {
                    errorText = 'referral.withdraw_min_error'.tr(namedArgs: {'min': minAmount.toStringAsFixed(2)});
                  });
                  return;
                }

                const epsilon = 0.0001;
                if (amount - currentBalance > epsilon) {
                  setState(() {
                    errorText = 'referral.withdraw_balance_insufficient'.tr();
                  });
                  return;
                }

                if (!hasInfoFor(withdrawMethod)) {
                  setState(() {
                    errorText = withdrawMethod == 'bank'
                        ? 'referral.withdraw_bank_info_required'.tr()
                        : 'referral.withdraw_paypal_info_required'.tr();
                  });
                  return;
                }

                setState(() {
                  errorText = null;
                  submitting = true;
                });

                try {
                  await pizApi.ApiService.ensureSidCookie(pizCloudServerUrl);

                  // Old http-based implementation (kept for reference)
                  // final base = pizCloudServerUrl.replaceAll(RegExp(r'/+$'), '');
                  // final uri = Uri.parse('$base/papi/referral/withdrawals');
                  // final jsonHeaders = authHeaders.authJson();
                  // final res = await http.post(
                  //   uri,
                  //   headers: jsonHeaders,
                  //   body: jsonEncode({
                  //     'email': userEmail,
                  //     'amount': amount,
                  //     'currency': currentCurrency,
                  //     'method': withdrawMethod,
                  //   }),
                  // );

                  // New Dio-based implementation using shared CookieJar (sid) + headers
                  final res = await pizApiService.client.post<dynamic>(
                    '/papi/referral/withdrawals',
                    data: {'email': userEmail, 'amount': amount, 'currency': currentCurrency, 'method': withdrawMethod},
                  );

                  final status = res.statusCode ?? 0;
                  if (status < 200 || status >= 300) {
                    String? code;
                    try {
                      final body = res.data;
                      if (body is Map<String, dynamic>) {
                        final msg = body['message'];
                        if (msg is String) {
                          code = msg;
                        } else if (msg is List && msg.isNotEmpty && msg.first is String) {
                          code = msg.first as String;
                        }
                      }
                    } catch (_) {}

                    switch (code) {
                      case 'MIN_TOTAL_COMMISSION_NOT_REACHED':
                        setState(() {
                          errorText = 'referral.withdraw_min_total_not_reached'.tr(
                            namedArgs: {'min': minAmount.toStringAsFixed(2)},
                          );
                        });
                        break;
                      case 'AMOUNT_EXCEEDS_BALANCE':
                      case 'AMOUNT_EXCEEDS_AVAILABLE_AFTER_PENDING':
                        setState(() {
                          errorText = 'referral.withdraw_balance_insufficient'.tr();
                        });
                        break;
                      case 'INVALID_AMOUNT':
                        setState(() {
                          errorText = 'referral.withdraw_amount_invalid'.tr();
                        });
                        break;
                      case 'INVALID_WITHDRAW_METHOD':
                        setState(() {
                          errorText = 'referral.withdraw_method_invalid'.tr();
                        });
                        break;
                      case 'BANK_INFO_REQUIRED':
                        setState(() {
                          errorText = 'referral.withdraw_bank_info_required'.tr();
                        });
                        break;
                      case 'PAYPAL_INFO_REQUIRED':
                        setState(() {
                          errorText = 'referral.withdraw_paypal_info_required'.tr();
                        });
                        break;
                      case 'USER_NOT_FOUND':
                      case 'EMAIL_REQUIRED':
                        setState(() {
                          errorText = 'referral.apply_missing_email'.tr();
                        });
                        break;
                      default:
                        setState(() {
                          errorText = 'referral.withdraw_request_error'.tr();
                        });
                    }

                    return;
                  }

                  if (context.mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('referral.withdraw_request_success'.tr())));
                    await loadSummary();
                  }
                } catch (e, s) {
                  debugPrint('Error requesting withdrawal: $e\n$s');
                  setState(() {
                    errorText = 'referral.withdraw_request_error'.tr();
                  });
                } finally {
                  setState(() {
                    submitting = false;
                  });
                }
              }

              String buildPayoutSummary(String method) {
                if (payout == null) return 'referral.withdraw_no_payout_info'.tr();
                if (method == 'bank') {
                  if (!hasInfoFor('bank')) {
                    return 'referral.withdraw_bank_info_required'.tr();
                  }
                  return [
                    payout.bankName ?? '',
                    payout.bankAccountNumber ?? '',
                    payout.bankAccountHolderName ?? '',
                  ].where((e) => e.isNotEmpty).join(' • ');
                } else {
                  if (!hasInfoFor('paypal')) {
                    return 'referral.withdraw_paypal_info_required'.tr();
                  }
                  final parts = [
                    payout.paypalEmail ?? '',
                    payout.paypalFullName ?? '',
                  ].where((e) => e.isNotEmpty).toList();
                  return parts.isEmpty ? 'referral.withdraw_paypal_info_required'.tr() : parts.join(' • ');
                }
              }

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text(
                  'referral.withdraw_title'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'referral.withdraw_description'.tr(namedArgs: {'min': minAmount.toStringAsFixed(2)}),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'referral.withdraw_balance_label'.tr(
                          namedArgs: {'balance': formatCurrency(currentBalance, currentCurrency)},
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'referral.withdraw_method_label'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: Text('referral.withdraw_method_bank'.tr()),
                              selected: withdrawMethod == 'bank',
                              onSelected: (v) {
                                if (!v) return;
                                setState(() {
                                  withdrawMethod = 'bank';
                                  errorText = null;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Text('referral.withdraw_method_paypal'.tr()),
                              selected: withdrawMethod == 'paypal',
                              onSelected: (v) {
                                if (!v) return;
                                setState(() {
                                  withdrawMethod = 'paypal';
                                  errorText = null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            buildPayoutSummary(withdrawMethod),
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 2),
                          TextButton(
                            onPressed: goEditPayout,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text('referral.withdraw_edit_payout_method'.tr(), textAlign: TextAlign.center),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'referral.withdraw_amount_label'.tr(),
                          hintText: 'referral.withdraw_amount_hint'.tr(),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onSubmitted: (_) => submit(),
                      ),
                      if (errorText != null && errorText!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(errorText!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.red.shade500)),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: submitting ? null : () => Navigator.of(ctx).pop(), child: Text('cancel'.tr())),
                  ElevatedButton(
                    onPressed: submitting ? null : submit,
                    style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
                    child: submitting
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('referral.withdraw_submit'.tr()),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    Widget buildLoadedBody() {
      final canWithdraw = totalCommissionPaid.value >= minWithdrawAmount && availableBalance.value > 0;

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
              availableBalance: availableBalance.value,
            ),

            // Withdraw section
            const SizedBox(height: 12),
            _WithdrawSection(
              canWithdraw: canWithdraw,
              minWithdrawAmount: minWithdrawAmount,
              totalCommission: availableBalance.value,
              currency: currency.value,
              onTap: openWithdrawDialog,
              onEditPayoutMethod: () {
                if (userEmail == null || userEmail!.isEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('referral.withdraw_missing_email'.tr())));
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReferralPayoutMethodPage(
                      userEmail: userEmail!,
                      onSaved: () {
                        loadPayoutMethod();
                        loadSummary();
                      },
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  if (userEmail == null || userEmail!.isEmpty) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('referral.withdraw_missing_email'.tr())));
                    return;
                  }
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => ReferralWithdrawalsPage(userEmail: userEmail!)));
                },
                child: Text('referral.withdraw_history_button'.tr()),
              ),
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
  const _SummaryStats({
    required this.totalReferredUsers,
    required this.totalCommission,
    required this.currency,
    required this.availableBalance,
  });

  final int totalReferredUsers;
  final double totalCommission;
  final String currency;
  final double availableBalance;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(label: 'referral.total_users'.tr(), value: totalReferredUsers.toString()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'referral.total_commission'.tr(),
                value: formatCurrency(totalCommission, currency),
              ),
            ),
          ],
        ),
        // const SizedBox(height: 8),
        // _StatCard(label: 'referral.available_balance'.tr(), value: formatCurrency(availableBalance, currency)),
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

class _WithdrawSection extends StatelessWidget {
  const _WithdrawSection({
    required this.canWithdraw,
    required this.minWithdrawAmount,
    required this.totalCommission,
    required this.currency,
    required this.onTap,
    required this.onEditPayoutMethod,
  });

  final bool canWithdraw;
  final double minWithdrawAmount;
  final double totalCommission;
  final String currency;
  final VoidCallback onTap;
  final VoidCallback onEditPayoutMethod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.9);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'referral.withdraw_section_title'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'referral.withdraw_section_hint'.tr(namedArgs: {'min': minWithdrawAmount.toStringAsFixed(2)}),
            style: theme.textTheme.bodySmall?.copyWith(color: textColor),
          ),
          // const SizedBox(height: 8),
          // InkWell(
          //   onTap: onEditPayoutMethod,
          //   child: Text(
          //     'referral.withdraw_edit_payout_method'.tr(),
          //     style: theme.textTheme.bodySmall?.copyWith(
          //       color: theme.colorScheme.primary,
          //       decoration: TextDecoration.underline,
          //     ),
          //   ),
          // ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'referral.withdraw_balance_label'.tr(
                    namedArgs: {'balance': formatCurrency(totalCommission, currency)},
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 36,
                child: _PillButton(
                  label: 'referral.withdraw_button'.tr(),
                  onPressed: canWithdraw
                      ? onTap
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'referral.withdraw_min_total_not_reached'.tr(
                                  namedArgs: {'min': minWithdrawAmount.toStringAsFixed(2)},
                                ),
                              ),
                            ),
                          );
                        },
                  primary: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
