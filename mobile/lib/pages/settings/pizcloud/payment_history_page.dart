import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/pizcloud/payment_history.model.dart';
import 'package:immich_mobile/services/pizcloud/payment_history.service.dart';

@RoutePage()
class PaymentHistoryPage extends HookConsumerWidget {
  const PaymentHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final loading = useState<bool>(true);
    final refreshing = useState<bool>(false);
    final loadingMore = useState<bool>(false);
    final error = useState<String?>(null);

    final items = useState<List<PaymentHistoryItem>>(<PaymentHistoryItem>[]);
    final page = useState<int>(1);
    final limit = useState<int>(20);
    final total = useState<int>(0);

    final statusFilter = useState<String>('paid');
    final platformFilter = useState<String>('all');
    final productIdController = useTextEditingController();
    final appliedProductIdFilter = useState<String?>(null);

    final requestIdRef = useRef<int>(0);

    Future<void> load({int pageNumber = 1, bool isRefresh = false, bool isLoadMore = false}) async {
      final requestId = ++requestIdRef.value;

      if (isRefresh) {
        refreshing.value = true;
      } else if (isLoadMore) {
        loadingMore.value = true;
      } else {
        loading.value = true;
      }

      if (!isLoadMore) {
        error.value = null;
      }

      try {
        final response = await paymentHistoryService.fetchPaymentHistory(
          page: pageNumber,
          limit: limit.value,
          status: statusFilter.value,
          platform: platformFilter.value,
          productId: appliedProductIdFilter.value,
        );

        if (requestId != requestIdRef.value) {
          return;
        }

        page.value = response.pagination.page;
        limit.value = response.pagination.limit;
        total.value = response.pagination.total;

        if (pageNumber == 1) {
          items.value = response.items;
          return;
        }

        final merged = <PaymentHistoryItem>[...items.value];
        final existingIds = merged.map((item) => item.id).where((id) => id.isNotEmpty).toSet();

        for (final item in response.items) {
          if (item.id.isNotEmpty && existingIds.contains(item.id)) {
            continue;
          }
          merged.add(item);
          if (item.id.isNotEmpty) {
            existingIds.add(item.id);
          }
        }

        items.value = merged;
      } catch (e, s) {
        debugPrint('Error loading payment history: $e\n$s');

        if (requestId != requestIdRef.value) {
          return;
        }

        if (pageNumber == 1) {
          error.value = 'payment_history.load_error'.tr();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('payment_history.load_error'.tr())));
        }
      } finally {
        if (requestId == requestIdRef.value) {
          if (isRefresh) {
            refreshing.value = false;
          } else if (isLoadMore) {
            loadingMore.value = false;
          } else {
            loading.value = false;
          }
        }
      }
    }

    useEffect(() {
      unawaited(load(pageNumber: 1));
      return null;
    }, const []);

    // void applyProductFilter() {
    //   final nextValue = productIdController.text.trim();
    //   appliedProductIdFilter.value = nextValue.isEmpty ? null : nextValue;
    //   unawaited(load(pageNumber: 1));
    // }

    // void clearProductFilter() {
    //   if (productIdController.text.isEmpty && appliedProductIdFilter.value == null) {
    //     return;
    //   }
    //   productIdController.clear();
    //   appliedProductIdFilter.value = null;
    //   unawaited(load(pageNumber: 1));
    // }

    Future<void> onRefresh() {
      return load(pageNumber: 1, isRefresh: true);
    }

    String formatAmount(double amount, String currencyCode) {
      final locale = context.locale.toString();
      try {
        final formatter = NumberFormat.currency(locale: locale, name: currencyCode);
        return formatter.format(amount);
      } catch (_) {
        try {
          final formatter = NumberFormat.currency(locale: 'en_US', name: currencyCode);
          return formatter.format(amount);
        } catch (_) {
          final decimal = NumberFormat.decimalPattern(locale);
          return '${decimal.format(amount)} $currencyCode';
        }
      }
    }

    String formatDateTime(DateTime? value) {
      if (value == null) {
        return '-';
      }
      final locale = context.locale.toString();
      final localValue = value.toLocal();
      return DateFormat('dd/MM/yyyy HH:mm', locale).format(localValue);
    }

    String statusLabel(String status) {
      switch (status) {
        case 'paid':
          return 'payment_history.status_paid'.tr();
        case 'failed':
          return 'payment_history.status_failed'.tr();
        case 'refunded':
          return 'payment_history.status_refunded'.tr();
        case 'pending':
          return 'payment_history.status_pending'.tr();
        case 'all':
          return 'payment_history.status_all'.tr();
        default:
          return status.isEmpty ? '-' : status;
      }
    }

    String platformLabel(String? platform) {
      switch (platform) {
        case 'android':
          return 'payment_history.platform_android'.tr();
        case 'ios':
          return 'payment_history.platform_ios'.tr();
        case 'all':
          return 'payment_history.platform_all'.tr();
        case null:
        case '':
          return 'payment_history.platform_unknown'.tr();
        default:
          return platform;
      }
    }

    String kindLabel(String kind) {
      switch (kind) {
        case 'activated':
          return 'payment_history.kind_activated'.tr();
        case 'renewed':
          return 'payment_history.kind_renewed'.tr();
        default:
          return 'payment_history.kind_unknown'.tr();
      }
    }

    String billingPeriodLabel(String? period) {
      switch (period) {
        case 'monthly':
          return 'subscription.period_monthly'.tr();
        case 'yearly':
        case 'annual':
          return 'subscription.period_yearly'.tr();
        case null:
        case '':
          return '-';
        default:
          return period;
      }
    }

    Color statusBackgroundColor(String status) {
      switch (status) {
        case 'paid':
          return Colors.green.shade50;
        case 'failed':
          return Colors.red.shade50;
        case 'refunded':
          return Colors.blue.shade50;
        case 'pending':
          return Colors.amber.shade50;
        default:
          return theme.colorScheme.surfaceContainerHighest;
      }
    }

    Color statusTextColor(String status) {
      switch (status) {
        case 'paid':
          return Colors.green.shade700;
        case 'failed':
          return Colors.red.shade700;
        case 'refunded':
          return Colors.blue.shade700;
        case 'pending':
          return Colors.amber.shade800;
        default:
          return theme.colorScheme.onSurfaceVariant;
      }
    }

    bool hasMore() {
      return items.value.length < total.value;
    }

    Widget buildFilterPanel() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // _FilterChipBar(
          //   title: 'payment_history.filter_status'.tr(),
          //   current: statusFilter.value,
          //   options: <String, String>{
          //     'paid': 'payment_history.status_paid'.tr(),
          //     'pending': 'payment_history.status_pending'.tr(),
          //     'failed': 'payment_history.status_failed'.tr(),
          //     'refunded': 'payment_history.status_refunded'.tr(),
          //     'all': 'payment_history.status_all'.tr(),
          //   },
          //   onChanged: (value) {
          //     if (value == statusFilter.value) {
          //       return;
          //     }
          //     statusFilter.value = value;
          //     unawaited(load(pageNumber: 1));
          //   },
          // ),
          // const SizedBox(height: 10),
          // _FilterChipBar(
          //   title: 'payment_history.filter_platform'.tr(),
          //   current: platformFilter.value,
          //   options: <String, String>{
          //     'all': 'payment_history.platform_all'.tr(),
          //     'android': 'payment_history.platform_android'.tr(),
          //     'ios': 'payment_history.platform_ios'.tr(),
          //   },
          //   onChanged: (value) {
          //     if (value == platformFilter.value) {
          //       return;
          //     }
          //     platformFilter.value = value;
          //     unawaited(load(pageNumber: 1));
          //   },
          // ),
          // const SizedBox(height: 10),
          // TextField(
          //   controller: productIdController,
          //   decoration: InputDecoration(
          //     labelText: 'payment_history.filter_product_id'.tr(),
          //     isDense: true,
          //     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          //   ),
          //   onSubmitted: (_) => applyProductFilter(),
          // ),
          // const SizedBox(height: 8),
          // Row(
          //   children: [
          //     Expanded(
          //       child: OutlinedButton(onPressed: applyProductFilter, child: Text('payment_history.apply_filter'.tr())),
          //     ),
          //     const SizedBox(width: 8),
          //     Expanded(
          //       child: OutlinedButton(onPressed: clearProductFilter, child: Text('payment_history.clear_filter'.tr())),
          //     ),
          //   ],
          // ),
          const SizedBox(height: 8),
          Text(
            'payment_history.total_results'.tr(namedArgs: {'count': total.value.toString()}),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8)),
          ),
        ],
      );
    }

    Widget buildPaymentCard(PaymentHistoryItem item, bool isLast) {
      final dividerColor = theme.dividerColor.withValues(alpha: 0.35);
      final kindText = kindLabel(item.kind);
      final platformText = platformLabel(item.platform);
      final periodText = billingPeriodLabel(item.billingPeriod);
      final statusText = statusLabel(item.status);

      return Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatAmount(item.finalAmount, item.currency),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${'payment_history.amount'.tr()}: ${formatAmount(item.amount, item.currency)} • '
                        '${'payment_history.discount'.tr()}: ${formatAmount(item.discountAmount, item.currency)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBackgroundColor(item.status),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusTextColor(item.status).withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    statusText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: statusTextColor(item.status),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _InfoLine(label: 'payment_history.kind'.tr(), value: kindText),
            _InfoLine(label: 'payment_history.platform'.tr(), value: platformText),
            if (item.productId != null && item.productId!.isNotEmpty)
              _InfoLine(label: 'payment_history.product_id'.tr(), value: item.productId!),
            if (item.planCode != null && item.planCode!.isNotEmpty)
              _InfoLine(label: 'payment_history.plan'.tr(), value: item.planCode!),
            if (item.planSizeGb != null)
              _InfoLine(label: 'payment_history.plan_size'.tr(), value: '${item.planSizeGb} GB'),
            _InfoLine(label: 'payment_history.billing_period'.tr(), value: periodText),
            _InfoLine(label: 'payment_history.renewal_number'.tr(), value: item.renewalNumber.toString()),
            _InfoLine(label: 'payment_history.created_at'.tr(), value: formatDateTime(item.createdAt)),
            _InfoLine(label: 'payment_history.period_end'.tr(), value: formatDateTime(item.periodEndAt)),
            if (item.providerTransactionId != null && item.providerTransactionId!.isNotEmpty)
              _InfoLine(label: 'payment_history.transaction_id'.tr(), value: item.providerTransactionId!),
          ],
        ),
      );
    }

    Widget buildBody() {
      final canLoadMore = hasMore();

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
                OutlinedButton(onPressed: () => unawaited(load(pageNumber: 1)), child: Text('retry'.tr())),
              ],
            ),
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: 1 + items.value.length + (canLoadMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildFilterPanel(),
                  if (items.value.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Center(
                        child: Text(
                          'payment_history.empty'.tr(),
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  if (items.value.isNotEmpty) const SizedBox(height: 12),
                ],
              );
            }

            final itemIndex = index - 1;
            if (itemIndex >= items.value.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(
                    onPressed: loadingMore.value
                        ? null
                        : () => unawaited(load(pageNumber: page.value + 1, isLoadMore: true)),
                    child: loadingMore.value
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('payment_history.load_more'.tr()),
                  ),
                ),
              );
            }

            final item = items.value[itemIndex];
            return buildPaymentCard(item, itemIndex == items.value.length - 1);
          },
        ),
      );
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text('payment_history.title'.tr())),
      body: SafeArea(
        child: Stack(
          children: [
            buildBody(),
            if (refreshing.value)
              const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
          ],
        ),
      ),
    );
  }
}

// class _FilterChipBar extends StatelessWidget {
//   const _FilterChipBar({required this.title, required this.current, required this.options, required this.onChanged});

//   final String title;
//   final String current;
//   final Map<String, String> options;
//   final ValueChanged<String> onChanged;

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
//         const SizedBox(height: 6),
//         SingleChildScrollView(
//           scrollDirection: Axis.horizontal,
//           child: Row(
//             children: options.entries.map((entry) {
//               final selected = current == entry.key;
//               return Padding(
//                 padding: const EdgeInsets.only(right: 8),
//                 child: ChoiceChip(
//                   label: Text(entry.value),
//                   selected: selected,
//                   onSelected: (value) {
//                     if (!value) {
//                       return;
//                     }
//                     onChanged(entry.key);
//                   },
//                 ),
//               );
//             }).toList(),
//           ),
//         ),
//       ],
//     );
//   }
// }

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        '$label: $value',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.9)),
      ),
    );
  }
}
