// mobile/lib/pages/settings/pizcloud/referral_withdrawals_page.dart

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
// import 'package:intl/intl.dart';

import 'package:immich_mobile/models/pizcloud/referral_withdrawal.model.dart';
import 'package:immich_mobile/services/pizcloud/referral_withdrawal.service.dart';

@RoutePage()
class ReferralWithdrawalsPage extends HookConsumerWidget {
  const ReferralWithdrawalsPage({super.key, required this.userEmail});

  final String userEmail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final loading = useState<bool>(true);
    final error = useState<String?>(null);
    final items = useState<List<ReferralWithdrawal>>(<ReferralWithdrawal>[]);
    final page = useState<int>(1);
    final limit = useState<int>(20);
    final total = useState<int>(0);
    final refreshing = useState<bool>(false);

    final statusFilter = useState<String>('all'); // 'all' | 'pending' | 'approved' | 'rejected' | 'paid'

    String formatDateTime(DateTime? dt) {
      if (dt == null) return '';
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    }

    String formatAmount(double amount, String currency) {
      try {
        final nf = NumberFormat.currency(locale: 'vi_VN', name: currency);
        return nf.format(amount);
      } catch (_) {
        final nf = NumberFormat.decimalPattern('vi_VN');
        return '${nf.format(amount)} $currency';
      }
    }

    Color statusBg(String status, ColorScheme scheme) {
      switch (status) {
        case 'paid':
          return Colors.green.shade50;
        case 'approved':
          return Colors.blue.shade50;
        case 'rejected':
          return Colors.red.shade50;
        case 'pending':
        default:
          return Colors.amber.shade50;
      }
    }

    Color statusText(String status, ColorScheme scheme) {
      switch (status) {
        case 'paid':
          return Colors.green.shade700;
        case 'approved':
          return Colors.blue.shade700;
        case 'rejected':
          return Colors.red.shade700;
        case 'pending':
        default:
          return Colors.amber.shade800;
      }
    }

    String statusLabel(String status) {
      switch (status) {
        case 'paid':
          return 'referral.withdraw_status_paid'.tr();
        case 'approved':
          return 'referral.withdraw_status_approved'.tr();
        case 'rejected':
          return 'referral.withdraw_status_rejected'.tr();
        case 'pending':
        default:
          return 'referral.withdraw_status_pending'.tr();
      }
    }

    String methodLabel(String method) {
      switch (method) {
        case 'paypal':
          return 'referral.withdraw_method_paypal'.tr();
        case 'bank':
        default:
          return 'referral.withdraw_method_bank'.tr();
      }
    }

    String payoutSummary(ReferralWithdrawal w) {
      if (w.method == 'bank') {
        final parts = [
          w.bankName ?? '',
          w.bankAccountNumber ?? '',
          w.bankAccountHolderName ?? '',
        ].where((e) => e.isNotEmpty).toList();
        if (parts.isEmpty) {
          return 'referral.withdraw_bank_info_required'.tr();
        }
        return parts.join(' • ');
      } else {
        final parts = [w.paypalEmail ?? '', w.paypalFullName ?? ''].where((e) => e.isNotEmpty).toList();
        if (parts.isEmpty) {
          return 'referral.withdraw_paypal_info_required'.tr();
        }
        return parts.join(' • ');
      }
    }

    Future<void> load({int pageNumber = 1, bool isRefresh = false}) async {
      if (userEmail.isEmpty) {
        loading.value = false;
        error.value = 'referral.withdraw_missing_email'.tr();
        return;
      }

      if (isRefresh) {
        refreshing.value = true;
      } else {
        loading.value = true;
      }
      error.value = null;

      try {
        final statusValue = statusFilter.value == 'all' ? null : statusFilter.value;

        final resp = await referralWithdrawalService.fetchWithdrawals(
          email: userEmail,
          page: pageNumber,
          limit: limit.value,
          status: statusValue,
        );

        page.value = resp.page;
        limit.value = resp.limit;
        total.value = resp.total;

        if (pageNumber == 1) {
          items.value = resp.items;
        } else {
          items.value = [...items.value, ...resp.items];
        }
      } catch (e, s) {
        debugPrint('Error loading withdrawals: $e\n$s');
        error.value = 'referral.withdraw_history_load_error'.tr();
      } finally {
        if (isRefresh) {
          refreshing.value = false;
        } else {
          loading.value = false;
        }
      }
    }

    useEffect(() {
      load(pageNumber: 1);
      return null;
    }, const []);

    Future<void> onRefresh() => load(pageNumber: 1, isRefresh: true);

    Widget buildBody() {
      final visibleItems = statusFilter.value == 'all'
          ? items.value
          : items.value.where((w) => w.status == statusFilter.value).toList();

      final hasMore = items.value.length < total.value;

      if (loading.value && items.value.isEmpty && error.value == null) {
        return const Center(child: CircularProgressIndicator());
      }

      if (error.value != null && items.value.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.value!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: OutlinedButton(onPressed: () => load(pageNumber: 1), child: Text('retry'.tr())),
                ),
              ],
            ),
          ),
        );
      }

      if (items.value.isEmpty) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusFilterBar(
                current: statusFilter.value,
                onChanged: (value) {
                  statusFilter.value = value;
                  load(pageNumber: 1);
                },
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'referral.withdraw_history_empty'.tr(),
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      }

      if (visibleItems.isEmpty && !hasMore) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusFilterBar(
                current: statusFilter.value,
                onChanged: (value) {
                  statusFilter.value = value;
                  load(pageNumber: 1);
                },
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'referral.withdraw_history_empty'.tr(),
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: 1 + visibleItems.length + (hasMore ? 1 : 0),
          itemBuilder: (ctx, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusFilterBar(
                    current: statusFilter.value,
                    onChanged: (value) {
                      statusFilter.value = value;
                      load(pageNumber: 1);
                    },
                  ),
                  if (visibleItems.isEmpty && hasMore == false)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('referral.withdraw_history_empty'.tr(), style: theme.textTheme.bodySmall),
                    ),
                ],
              );
            }

            final itemIndex = index - 1;

            if (itemIndex >= visibleItems.length) {
              // Row load more
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(
                    onPressed: loading.value ? null : () => load(pageNumber: page.value + 1),
                    child: loading.value
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('referral.withdraw_history_load_more'.tr()),
                  ),
                ),
              );
            }

            final w = visibleItems[itemIndex];
            final colorScheme = theme.colorScheme;
            final dividerColor = theme.dividerColor.withValues(alpha: 0.4);

            return Container(
              margin: EdgeInsets.only(bottom: itemIndex == visibleItems.length - 1 ? 0 : 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Amount + status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatAmount(w.amount, w.currency),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              methodLabel(w.method),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusBg(w.status, colorScheme),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: statusText(w.status, colorScheme).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          statusLabel(w.status),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: statusText(w.status, colorScheme),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Payout info
                  Text(
                    payoutSummary(w),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Dates
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (w.createdAt != null)
                        Text(
                          'referral.withdraw_created_at'.tr(namedArgs: {'date': formatDateTime(w.createdAt)}),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                          ),
                        ),
                      if (w.processedAt != null)
                        Text(
                          'referral.withdraw_processed_at'.tr(namedArgs: {'date': formatDateTime(w.processedAt)}),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                  if ((w.note ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'referral.withdraw_user_note'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(w.note!, style: theme.textTheme.bodySmall),
                  ],
                  if ((w.adminNote ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'referral.withdraw_admin_note'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      w.adminNote!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text('referral.withdraw_history_title'.tr())),
      body: SafeArea(child: buildBody()),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.current, required this.onChanged});

  final String current; // 'all' | 'pending' | 'approved' | 'rejected' | 'paid'
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <String, String>{
      'all': 'referral.withdraw_filter_all'.tr(),
      'pending': 'referral.withdraw_status_pending'.tr(),
      'approved': 'referral.withdraw_status_approved'.tr(),
      'rejected': 'referral.withdraw_status_rejected'.tr(),
      'paid': 'referral.withdraw_status_paid'.tr(),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: options.entries.map((e) {
            final selected = current == e.key;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: selected,
                onSelected: (v) {
                  if (!v) return;
                  onChanged(e.key);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}