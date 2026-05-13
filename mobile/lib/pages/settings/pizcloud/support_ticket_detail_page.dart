import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/pizcloud/support_ticket.model.dart';
import 'package:immich_mobile/services/pizcloud/support_ticket.service.dart';

@RoutePage()
class SupportTicketDetailPage extends HookConsumerWidget {
  const SupportTicketDetailPage({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = useState<SupportTicketDetail?>(null);
    final loading = useState<bool>(true);
    final loadingAction = useState<bool>(false);
    final error = useState<String?>(null);

    final messageController = useTextEditingController();
    final replyAttachments = useState<List<PlatformFile>>(<PlatformFile>[]);

    Future<void> load() async {
      loading.value = true;
      error.value = null;

      try {
        final data = await supportTicketService.fetchTicketDetail(ticketId);
        detail.value = data;
      } on SupportTicketApiException catch (apiError) {
        error.value = _messageFromErrorCode(apiError.code ?? apiError.message).tr();
      } catch (_) {
        error.value = 'support_ticket.load_error'.tr();
      } finally {
        loading.value = false;
      }
    }

    useEffect(() {
      load();
      return null;
    }, const []);

    Future<void> pickReplyAttachments() async {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
      if (result == null || result.files.isEmpty) {
        return;
      }

      final merged = <PlatformFile>[...replyAttachments.value];
      for (final file in result.files) {
        final filePath = file.path?.trim() ?? '';
        if (filePath.isEmpty) {
          continue;
        }

        if (file.size > SupportTicketService.maxAttachmentBytes) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('support_ticket.error_attachment_too_large'.tr())));
          continue;
        }

        final exists = merged.any((existing) => existing.path == file.path);
        if (!exists) {
          merged.add(file);
        }
      }

      replyAttachments.value = merged;
    }

    Future<void> sendReply() async {
      final text = messageController.text.trim();
      if (text.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('support_ticket.error_message_required'.tr())));
        return;
      }

      loadingAction.value = true;
      try {
        final attachmentPaths = replyAttachments.value
            .map((file) => file.path?.trim() ?? '')
            .where((filePath) => filePath.isNotEmpty)
            .toList();

        final updated = await supportTicketService.replyTicket(
          ticketId: ticketId,
          message: text,
          attachmentPaths: attachmentPaths,
        );

        detail.value = updated;
        messageController.clear();
        replyAttachments.value = <PlatformFile>[];

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('support_ticket.reply_success'.tr())));
        }
      } on SupportTicketApiException catch (apiError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFromErrorCode(apiError.code ?? apiError.message).tr())));
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('support_ticket.reply_error'.tr())));
      } finally {
        loadingAction.value = false;
      }
    }

    Future<void> toggleStatus() async {
      final current = detail.value?.ticket.status.trim().toLowerCase();
      if (current == null || current.isEmpty) {
        return;
      }

      final nextStatus = current == 'closed' ? 'open' : 'closed';

      loadingAction.value = true;
      try {
        await supportTicketService.updateTicketStatus(ticketId: ticketId, status: nextStatus);
        await load();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                nextStatus == 'closed' ? 'support_ticket.close_success'.tr() : 'support_ticket.reopen_success'.tr(),
              ),
            ),
          );
        }
      } on SupportTicketApiException catch (apiError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFromErrorCode(apiError.code ?? apiError.message).tr())));
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('support_ticket.status_update_error'.tr())));
      } finally {
        loadingAction.value = false;
      }
    }

    final ticket = detail.value?.ticket;
    final isClosed = ticket?.status.trim().toLowerCase() == 'closed';

    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text('support_ticket.detail'.tr())),
      body: SafeArea(
        child: loading.value
            ? const Center(child: CircularProgressIndicator())
            : error.value != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error.value!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: load, child: Text('retry'.tr())),
                    ],
                  ),
                ),
              )
            : ticket == null
            ? Center(child: Text('support_ticket.error_ticket_not_found'.tr()))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.subject,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MetaBadge(label: _statusLabel(ticket.status).tr()),
                            _MetaBadge(label: _priorityLabel(ticket.priority).tr()),
                            _MetaBadge(label: _categoryLabel(ticket.category).tr()),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                ticket.updatedAt == null
                                    ? ''
                                    : 'support_ticket.updated_at'.tr(
                                        namedArgs: {
                                          'date': DateFormat('dd/MM/yyyy HH:mm').format(ticket.updatedAt!.toLocal()),
                                        },
                                      ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              onPressed: loadingAction.value ? null : toggleStatus,
                              child: Text(isClosed ? 'support_ticket.reopen'.tr() : 'support_ticket.close'.tr()),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: detail.value?.messages.length ?? 0,
                      itemBuilder: (context, index) {
                        final message = detail.value!.messages[index];
                        final isUser = message.senderType.trim().toLowerCase() == 'user';

                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 520),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isUser ? 'support_ticket.sender_you'.tr() : 'support_ticket.sender_support'.tr(),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text(message.message, style: Theme.of(context).textTheme.bodyMedium),
                                if (message.attachments.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  for (final attachment in message.attachments)
                                    Text('- ${attachment.fileName}', style: Theme.of(context).textTheme.bodySmall),
                                ],
                                if (message.createdAt != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    DateFormat('dd/MM/yyyy HH:mm').format(message.createdAt!.toLocal()),
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (!isClosed)
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Column(
                          children: [
                            TextField(
                              controller: messageController,
                              minLines: 2,
                              maxLines: 4,
                              decoration: InputDecoration(
                                hintText: 'support_ticket.reply_placeholder'.tr(),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: loadingAction.value ? null : pickReplyAttachments,
                                  icon: const Icon(Icons.attach_file),
                                  label: Text('support_ticket.add_attachment'.tr()),
                                ),
                                const Spacer(),
                                ElevatedButton(
                                  onPressed: loadingAction.value ? null : sendReply,
                                  child: loadingAction.value
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : Text('support_ticket.send_reply'.tr()),
                                ),
                              ],
                            ),
                            if (replyAttachments.value.isNotEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (var i = 0; i < replyAttachments.value.length; i++)
                                        InputChip(
                                          label: Text(replyAttachments.value[i].name),
                                          onDeleted: loadingAction.value
                                              ? null
                                              : () {
                                                  final current = [...replyAttachments.value];
                                                  current.removeAt(i);
                                                  replyAttachments.value = current;
                                                },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
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
    default:
      return 'support_ticket.category_other';
  }
}

String _messageFromErrorCode(String code) {
  final normalized = code.trim().toUpperCase();

  switch (normalized) {
    case 'ATTACHMENT_TOO_LARGE':
      return 'support_ticket.error_attachment_too_large';
    case 'MESSAGE_REQUIRED':
      return 'support_ticket.error_message_required';
    case 'TICKET_NOT_FOUND':
      return 'support_ticket.error_ticket_not_found';
    default:
      return 'support_ticket.load_error';
  }
}
