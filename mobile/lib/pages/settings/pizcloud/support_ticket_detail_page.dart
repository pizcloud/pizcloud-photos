import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/pizcloud/support_ticket.model.dart';
import 'package:immich_mobile/services/pizcloud/support_ticket.service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
    final refreshingDetailFuture = useRef<Future<SupportTicketDetail?>?>(null);
    final attachmentActionKeys = useState<Set<String>>(<String>{});

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

    Future<SupportTicketDetail?> refreshDetailSilently() async {
      final runningFuture = refreshingDetailFuture.value;
      if (runningFuture != null) {
        return runningFuture;
      }

      final nextFuture = () async {
        try {
          final data = await supportTicketService.fetchTicketDetail(ticketId);
          detail.value = data;
          return data;
        } catch (_) {
          return null;
        } finally {
          refreshingDetailFuture.value = null;
        }
      }();

      refreshingDetailFuture.value = nextFuture;
      return nextFuture;
    }

    SupportTicketAttachment? findAttachmentFromDetail(SupportTicketDetail? source, SupportTicketAttachment target) {
      if (source == null) {
        return null;
      }

      for (final message in source.messages) {
        for (final attachment in message.attachments) {
          if (target.id.isNotEmpty && attachment.id == target.id) {
            return attachment;
          }
          if (target.url.isNotEmpty && attachment.url == target.url) {
            return attachment;
          }
          if (attachment.fileName == target.fileName && attachment.size == target.size) {
            return attachment;
          }
        }
      }

      return null;
    }

    Future<Uint8List> loadAttachmentBytesWithRetry(SupportTicketAttachment inputAttachment) async {
      var currentAttachment = inputAttachment;

      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          return await supportTicketService.fetchAttachmentBytes(currentAttachment.url);
        } on SupportTicketApiException catch (apiError) {
          final normalizedCode = (apiError.code ?? apiError.message).trim().toUpperCase();
          if (attempt == 0 && _isAttachmentUrlExpiredCode(normalizedCode)) {
            final refreshedDetail = await refreshDetailSilently();
            final refreshedAttachment = findAttachmentFromDetail(refreshedDetail, currentAttachment);
            if (refreshedAttachment != null && refreshedAttachment.url.trim().isNotEmpty) {
              currentAttachment = refreshedAttachment;
              continue;
            }
          }
          rethrow;
        }
      }

      throw const SupportTicketApiException(
        message: 'Attachment URL expired',
        code: 'ATTACHMENT_URL_EXPIRED',
        statusCode: 403,
      );
    }

    Future<void> downloadAttachment(SupportTicketAttachment attachment) async {
      final actionKey = _attachmentIdentity(attachment);
      if (attachmentActionKeys.value.contains(actionKey)) {
        return;
      }

      attachmentActionKeys.value = <String>{...attachmentActionKeys.value, actionKey};

      try {
        final bytes = await loadAttachmentBytesWithRetry(attachment);
        final tempDir = await getTemporaryDirectory();
        final attachmentDir = Directory('${tempDir.path}/support_ticket_downloads');
        if (!await attachmentDir.exists()) {
          await attachmentDir.create(recursive: true);
        }

        final fileName = _resolveAttachmentFileName(attachment.fileName);
        final file = File('${attachmentDir.path}/${DateTime.now().millisecondsSinceEpoch}_$fileName');
        await file.writeAsBytes(bytes, flush: true);

        if (!context.mounted) {
          return;
        }

        final box = context.findRenderObject() as RenderBox?;
        final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;

        await Share.shareXFiles([XFile(file.path)], subject: fileName, sharePositionOrigin: origin);
      } on SupportTicketApiException catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('download_error'.tr())));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('download_error'.tr())));
        }
      } finally {
        final next = <String>{...attachmentActionKeys.value};
        next.remove(actionKey);
        attachmentActionKeys.value = next;
      }
    }

    Future<void> openAttachmentPreview(SupportTicketAttachment attachment) async {
      try {
        final bytes = await loadAttachmentBytesWithRetry(attachment);
        if (!context.mounted) {
          return;
        }

        await showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return Dialog(
              insetPadding: const EdgeInsets.all(12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    color: Theme.of(dialogContext).colorScheme.surfaceContainerHigh,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            attachment.fileName.isEmpty ? 'image'.tr() : attachment.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(dialogContext).textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: 'download'.tr(),
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            unawaited(downloadAttachment(attachment));
                          },
                          icon: const Icon(Icons.download_rounded),
                        ),
                        IconButton(
                          tooltip: 'close'.tr(),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 5,
                      child: Container(
                        color: Theme.of(dialogContext).colorScheme.surface,
                        constraints: const BoxConstraints(minHeight: 220),
                        alignment: Alignment.center,
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      } on SupportTicketApiException catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('download_error'.tr())));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('download_error'.tr())));
        }
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
                        final messages = detail.value!.messages;
                        final message = messages[index];
                        final normalizedSender = message.senderType.trim().toLowerCase();
                        final isUser = normalizedSender == 'user';
                        final nextMessage = index + 1 < messages.length ? messages[index + 1] : null;
                        final isNextSameSender =
                            nextMessage != null && nextMessage.senderType.trim().toLowerCase() == normalizedSender;
                        final bottomSpacing = isNextSameSender ? 14.0 : 10.0;

                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 520),
                            margin: EdgeInsets.only(bottom: bottomSpacing),
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
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _SupportTicketAttachmentTile(
                                        attachment: attachment,
                                        isImage: _isImageAttachment(attachment),
                                        isActionLoading: attachmentActionKeys.value.contains(
                                          _attachmentIdentity(attachment),
                                        ),
                                        loadImageBytes: loadAttachmentBytesWithRetry,
                                        onPreview: () => openAttachmentPreview(attachment),
                                        onDownload: () => downloadAttachment(attachment),
                                      ),
                                    ),
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

class _SupportTicketAttachmentTile extends StatelessWidget {
  const _SupportTicketAttachmentTile({
    required this.attachment,
    required this.isImage,
    required this.isActionLoading,
    required this.loadImageBytes,
    required this.onPreview,
    required this.onDownload,
  });

  final SupportTicketAttachment attachment;
  final bool isImage;
  final bool isActionLoading;
  final Future<Uint8List> Function(SupportTicketAttachment attachment) loadImageBytes;
  final VoidCallback onPreview;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    if (isImage) {
      return SizedBox(
        width: 164,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SupportTicketImageThumbnail(
              key: ValueKey<String>(_attachmentIdentity(attachment)),
              attachment: attachment,
              loadBytes: loadImageBytes,
              onTap: onPreview,
            ),
            const SizedBox(height: 6),
            Text(
              attachment.fileName.isEmpty ? 'image'.tr() : attachment.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatFileSize(attachment.size),
                    style: Theme.of(context).textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'download'.tr(),
                  onPressed: isActionLoading ? null : onDownload,
                  icon: const Icon(Icons.download_rounded, size: 18),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_rounded, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.fileName.isEmpty ? 'attachment' : attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 2),
                Text(_formatFileSize(attachment.size), style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'download'.tr(),
            onPressed: isActionLoading ? null : onDownload,
            icon: const Icon(Icons.download_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _SupportTicketImageThumbnail extends StatefulWidget {
  const _SupportTicketImageThumbnail({
    super.key,
    required this.attachment,
    required this.loadBytes,
    required this.onTap,
  });

  final SupportTicketAttachment attachment;
  final Future<Uint8List> Function(SupportTicketAttachment attachment) loadBytes;
  final VoidCallback onTap;

  @override
  State<_SupportTicketImageThumbnail> createState() => _SupportTicketImageThumbnailState();
}

class _SupportTicketImageThumbnailState extends State<_SupportTicketImageThumbnail> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadBytes(widget.attachment);
  }

  @override
  void didUpdateWidget(covariant _SupportTicketImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousKey = _attachmentIdentity(oldWidget.attachment);
    final nextKey = _attachmentIdentity(widget.attachment);
    if (previousKey != nextKey || oldWidget.attachment.url != widget.attachment.url) {
      _future = widget.loadBytes(widget.attachment);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 164,
          height: 112,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: FutureBuilder<Uint8List>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }

              if (snapshot.hasData) {
                return Image.memory(snapshot.data!, fit: BoxFit.cover);
              }

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image_outlined),
                  const SizedBox(height: 4),
                  Text('retry'.tr(), style: Theme.of(context).textTheme.labelSmall),
                ],
              );
            },
          ),
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

const Set<String> _imageAttachmentExtensions = <String>{
  'apng',
  'avif',
  'bmp',
  'gif',
  'heic',
  'heif',
  'jfif',
  'jpeg',
  'jpg',
  'png',
  'svg',
  'tif',
  'tiff',
  'webp',
};

bool _isImageAttachment(SupportTicketAttachment attachment) {
  final mimeType = attachment.mimeType.trim().toLowerCase();
  if (mimeType.startsWith('image/')) {
    return true;
  }

  final fileName = attachment.fileName.trim();
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == fileName.length - 1) {
    return false;
  }

  final extension = fileName.substring(dotIndex + 1).toLowerCase();
  return _imageAttachmentExtensions.contains(extension);
}

bool _isAttachmentUrlExpiredCode(String code) {
  return code == 'ATTACHMENT_URL_EXPIRED' || code == 'ATTACHMENT_URL_INVALID';
}

String _attachmentIdentity(SupportTicketAttachment attachment) {
  final id = attachment.id.trim();
  if (id.isNotEmpty) {
    return 'id:$id';
  }

  final url = attachment.url.trim();
  if (url.isNotEmpty) {
    return 'url:$url';
  }

  return 'name:${attachment.fileName}:${attachment.size}';
}

String _resolveAttachmentFileName(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return 'attachment.bin';
  }

  return normalized.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }

  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }

  return '${(kb / 1024).toStringAsFixed(1)} MB';
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
