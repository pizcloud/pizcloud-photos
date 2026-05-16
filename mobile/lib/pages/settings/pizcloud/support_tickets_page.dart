import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/pizcloud/support_ticket.model.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/pizcloud/support_ticket.service.dart';
import 'package:url_launcher/url_launcher.dart';

const String _faqBaseUrl = 'https://pizcloud.com';
const String _faqPath = '/en/faq/';

@RoutePage()
class SupportTicketsPage extends HookConsumerWidget {
  const SupportTicketsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final loading = useState<bool>(true);
    final loadingMore = useState<bool>(false);
    final refreshing = useState<bool>(false);
    final error = useState<String?>(null);
    final items = useState<List<SupportTicketItem>>(<SupportTicketItem>[]);

    final page = useState<int>(1);
    final limit = useState<int>(20);
    final total = useState<int>(0);
    final statusFilter = useState<String>('all');
    final faqUri = Uri.parse('$_faqBaseUrl$_faqPath');

    Future<void> load({int pageNumber = 1, bool isRefresh = false}) async {
      if (isRefresh) {
        refreshing.value = true;
      } else if (pageNumber == 1) {
        loading.value = true;
      } else {
        loadingMore.value = true;
      }

      error.value = null;

      try {
        final response = await supportTicketService.fetchTickets(
          page: pageNumber,
          limit: limit.value,
          status: statusFilter.value == 'all' ? null : statusFilter.value,
        );

        page.value = response.page;
        limit.value = response.limit;
        total.value = response.total;

        if (pageNumber == 1) {
          items.value = response.items;
        } else {
          items.value = [...items.value, ...response.items];
        }
      } on SupportTicketApiException catch (apiError) {
        error.value = _messageFromErrorCode(apiError.code ?? apiError.message).tr();
      } catch (_) {
        error.value = 'support_ticket.load_error'.tr();
      } finally {
        loading.value = false;
        loadingMore.value = false;
        refreshing.value = false;
      }
    }

    useEffect(() {
      load(pageNumber: 1);
      return null;
    }, const []);

    Future<void> openCreateTicket() async {
      final created = await context.pushRoute<bool>(const SupportTicketCreateRoute());
      if (created == true) {
        await load(pageNumber: 1, isRefresh: true);
      }
    }

    Future<void> openTicketDetail(String ticketId) async {
      await context.pushRoute<void>(SupportTicketDetailRoute(ticketId: ticketId));
      await load(pageNumber: 1, isRefresh: true);
    }

    Future<void> onRefresh() => load(pageNumber: 1, isRefresh: true);

    Future<void> openFaq() async {
      await launchUrl(faqUri, mode: LaunchMode.externalApplication);
    }

    Widget buildStatusFilter() {
      final filters = <String>['all', 'open', 'in_progress', 'waiting_user', 'resolved', 'closed'];

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_statusLabel(filter).tr()),
                  selected: statusFilter.value == filter,
                  onSelected: (selected) {
                    if (!selected || statusFilter.value == filter) {
                      return;
                    }

                    statusFilter.value = filter;
                    load(pageNumber: 1);
                  },
                ),
              ),
          ],
        ),
      );
    }

    Widget buildList() {
      final hasMore = items.value.length < total.value;

      if (loading.value && items.value.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      if (error.value != null && items.value.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.value!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => load(pageNumber: 1), child: Text('retry'.tr())),
              ],
            ),
          ),
        );
      }

      if (items.value.isEmpty) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              buildStatusFilter(),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'support_ticket.empty'.tr(),
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          itemCount: 1 + items.value.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(padding: const EdgeInsets.only(bottom: 12), child: buildStatusFilter());
            }

            final itemIndex = index - 1;
            if (itemIndex >= items.value.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: loadingMore.value
                        ? null
                        : () {
                            load(pageNumber: page.value + 1);
                          },
                    child: loadingMore.value
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('support_ticket.load_more'.tr()),
                  ),
                ),
              );
            }

            final ticket = items.value[itemIndex];
            final updatedAt = ticket.updatedAt ?? ticket.createdAt;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => openTicketDetail(ticket.id),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ticket.subject,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusBadge(status: ticket.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _MetaBadge(label: _categoryLabel(ticket.category).tr()),
                          _MetaBadge(label: _priorityLabel(ticket.priority).tr()),
                          if (ticket.attachments.isNotEmpty)
                            _MetaBadge(
                              label: 'support_ticket.attachment_count'.tr(
                                namedArgs: {'count': ticket.attachments.length.toString()},
                              ),
                            ),
                        ],
                      ),
                      if (ticket.latestMessage.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          ticket.latestMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              updatedAt == null
                                  ? ''
                                  : 'support_ticket.updated_at'.tr(
                                      namedArgs: {'date': DateFormat('dd/MM/yyyy HH:mm').format(updatedAt.toLocal())},
                                    ),
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          if (ticket.unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'support_ticket.unread_count'.tr(namedArgs: {'count': ticket.unreadCount.toString()}),
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text('support_ticket.title'.tr())),
      body: Column(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
              child: TextButton(onPressed: openFaq, child: Text('support_ticket.go_to_faq'.tr())),
            ),
          ),
          Expanded(child: buildList()),
        ],
      ),
      material: (_, __) => MaterialScaffoldData(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: openCreateTicket,
          icon: const Icon(Icons.add),
          label: Text('support_ticket.create'.tr()),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = status.trim().toLowerCase();

    Color fg;
    Color bg;
    switch (normalized) {
      case 'closed':
        fg = Colors.grey.shade700;
        bg = Colors.grey.shade200;
        break;
      case 'resolved':
        fg = Colors.green.shade700;
        bg = Colors.green.shade50;
        break;
      case 'in_progress':
        fg = Colors.blue.shade700;
        bg = Colors.blue.shade50;
        break;
      case 'waiting_user':
        fg = Colors.amber.shade800;
        bg = Colors.amber.shade50;
        break;
      case 'open':
      default:
        fg = theme.colorScheme.primary;
        bg = theme.colorScheme.primaryContainer;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        _statusLabel(status).tr(),
        style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

String _statusLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'open':
      return 'support_ticket.status_open';
    case 'in_progress':
      return 'support_ticket.status_in_progress';
    case 'waiting_user':
      return 'support_ticket.status_waiting_user';
    case 'resolved':
      return 'support_ticket.status_resolved';
    case 'closed':
      return 'support_ticket.status_closed';
    case 'all':
    default:
      return 'support_ticket.status_all';
  }
}

String _priorityLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'low':
      return 'support_ticket.priority_low';
    case 'high':
      return 'support_ticket.priority_high';
    case 'urgent':
      return 'support_ticket.priority_urgent';
    case 'normal':
    default:
      return 'support_ticket.priority_normal';
  }
}

String _categoryLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'bug':
      return 'support_ticket.category_bug';
    case 'billing':
      return 'support_ticket.category_billing';
    case 'account':
      return 'support_ticket.category_account';
    case 'feature':
      return 'support_ticket.category_feature';
    case 'other':
    default:
      return 'support_ticket.category_other';
  }
}

String _messageFromErrorCode(String code) {
  final normalized = code.trim().toUpperCase();

  switch (normalized) {
    case 'ATTACHMENT_TOO_LARGE':
      return 'support_ticket.error_attachment_too_large';
    case 'SUBJECT_REQUIRED':
      return 'support_ticket.error_subject_required';
    case 'MESSAGE_REQUIRED':
      return 'support_ticket.error_message_required';
    case 'TICKET_NOT_FOUND':
      return 'support_ticket.error_ticket_not_found';
    default:
      return 'support_ticket.load_error';
  }
}
