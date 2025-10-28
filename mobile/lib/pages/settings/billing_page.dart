import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:immich_mobile/features/billing/billing_controller.dart';
import 'package:immich_mobile/providers/billing.provider.dart';

Color _bannerColor(String s) {
  switch (s) {
    case 'warn':
      return Colors.amber.shade200;
    case 'critical':
      return Colors.orange.shade300;
    case 'blocked':
      return Colors.red.shade300;
    default:
      return Colors.green.shade200;
  }
}

class BillingPage extends HookConsumerWidget {
  const BillingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(billingControllerProvider) as dynamic;
    final ctl = ref.read(billingControllerProvider.notifier) as BillingController;

    final usage = state.usage as Map<String, dynamic>?;
    final products = (state.products as List<ProductDetails>? ?? const []);

    return Scaffold(
      appBar: AppBar(title: const Text('Billing & Storage')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (usage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _bannerColor(usage['state'] as String),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Usage: ${usage['used_gb']} / ${usage['limit_gb']} GB (${usage['percent']}%)',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: ((usage['percent'] as num) / 100).clamp(0, 1).toDouble()),
                          if (usage['state'] == 'warn')
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text('You have used > 80%. Consider upgrading your plan.'),
                            ),
                          if (usage['state'] == 'critical')
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text('You have used > 90%. Very close to the maximum!'),
                            ),
                          if (usage['state'] == 'blocked')
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'OUT OF STORAGE - Uploads will be blocked.',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (state.error != null) Text(state.error!, style: const TextStyle(color: Colors.red)),
                  if (state.entitlement != null) ...[
                    Text('Current plan: ${state.entitlement!['plan_code']}'),
                    Text('Storage: ${state.entitlement!['storage_limit_gb']} GB'),
                    TextButton(onPressed: ctl.refreshUsage, child: const Text('Refresh usage')),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, i) {
                        final p = products[i];
                        return ListTile(
                          title: Text(p.title),
                          subtitle: Text(p.description),
                          trailing: ElevatedButton(onPressed: () => ctl.buy(p), child: Text(p.price)),
                        );
                      },
                    ),
                  ),
                  Center(
                    child: TextButton(onPressed: ctl.restore, child: const Text('Restore Purchases')),
                  ),
                ],
              ),
      ),
    );
  }
}

// // lib/pages/common/upgrade.page.dart
// import 'package:auto_route/auto_route.dart';
// import 'package:flutter/material.dart';

// @RoutePage()
// class BillingPage extends StatelessWidget {
//   const BillingPage({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Upgrade')),
//       body: const Center(child: Text('Content')),
//     );
//   }
// }
