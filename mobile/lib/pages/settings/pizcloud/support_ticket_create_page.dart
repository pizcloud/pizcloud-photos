import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/pizcloud/support_ticket.service.dart';

@RoutePage()
class SupportTicketCreatePage extends HookConsumerWidget {
  const SupportTicketCreatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final subjectController = useTextEditingController();
    final messageController = useTextEditingController();

    final selectedCategory = useState<String>('bug');
    final selectedPriority = useState<String>('normal');
    final attachments = useState<List<PlatformFile>>(<PlatformFile>[]);

    final submitting = useState<bool>(false);
    final errorMessage = useState<String?>(null);

    Future<void> pickAttachments() async {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
      if (result == null || result.files.isEmpty) {
        return;
      }

      final merged = <PlatformFile>[...attachments.value];
      for (final file in result.files) {
        final filePath = file.path?.trim() ?? '';
        if (filePath.isEmpty) {
          continue;
        }

        if (file.size > SupportTicketService.maxAttachmentBytes) {
          errorMessage.value = 'support_ticket.error_attachment_too_large'.tr();
          continue;
        }

        final exists = merged.any((existing) => existing.path == file.path);
        if (!exists) {
          merged.add(file);
        }
      }

      attachments.value = merged;
    }

    Future<void> submit() async {
      FocusScope.of(context).unfocus();

      if (!(formKey.currentState?.validate() ?? false)) {
        return;
      }

      submitting.value = true;
      errorMessage.value = null;

      try {
        final attachmentPaths = attachments.value
            .map((file) => file.path?.trim() ?? '')
            .where((filePath) => filePath.isNotEmpty)
            .toList();

        await supportTicketService.createTicket(
          subject: subjectController.text,
          category: selectedCategory.value,
          priority: selectedPriority.value,
          message: messageController.text,
          attachmentPaths: attachmentPaths,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('support_ticket.create_success'.tr())));
          Navigator.of(context).pop(true);
        }
      } on SupportTicketApiException catch (apiError) {
        errorMessage.value = _messageFromErrorCode(apiError.code ?? apiError.message).tr();
      } catch (_) {
        errorMessage.value = 'support_ticket.create_error'.tr();
      } finally {
        submitting.value = false;
      }
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text('support_ticket.create'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('support_ticket.create_description'.tr(), style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                TextFormField(
                  controller: subjectController,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: 'support_ticket.subject'.tr(),
                    hintText: 'support_ticket.subject_hint'.tr(),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'support_ticket.error_subject_required'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _DropdownField(
                  label: 'support_ticket.category'.tr(),
                  value: selectedCategory.value,
                  items: const <String>['bug', 'billing', 'account', 'feature', 'other'],
                  itemLabelBuilder: _categoryLabel,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    selectedCategory.value = value;
                  },
                ),
                const SizedBox(height: 12),
                _DropdownField(
                  label: 'support_ticket.priority'.tr(),
                  value: selectedPriority.value,
                  items: const <String>['low', 'normal', 'high', 'urgent'],
                  itemLabelBuilder: _priorityLabel,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    selectedPriority.value = value;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: messageController,
                  minLines: 5,
                  maxLines: 8,
                  maxLength: 4000,
                  decoration: InputDecoration(
                    labelText: 'support_ticket.message'.tr(),
                    hintText: 'support_ticket.message_hint'.tr(),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'support_ticket.error_message_required'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: submitting.value ? null : pickAttachments,
                      icon: const Icon(Icons.attach_file),
                      label: Text('support_ticket.add_attachment'.tr()),
                    ),
                    const SizedBox(width: 8),
                    Text('support_ticket.attachment_limit'.tr(), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                if (attachments.value.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (var i = 0; i < attachments.value.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(attachments.value[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_formatFileSize(attachments.value[i].size)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: submitting.value
                            ? null
                            : () {
                                final current = [...attachments.value];
                                current.removeAt(i);
                                attachments.value = current;
                              },
                      ),
                    ),
                ],
                if (errorMessage.value != null && errorMessage.value!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage.value!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red.shade600),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: submitting.value ? null : submit,
                    child: submitting.value
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('support_ticket.submit'.tr()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabelBuilder,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final String Function(String value) itemLabelBuilder;
  final void Function(String? value) onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('${label}_$value'),
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
      items: [
        for (final item in items) DropdownMenuItem<String>(value: item, child: Text(itemLabelBuilder(item).tr())),
      ],
      onChanged: onChanged,
    );
  }
}

String _categoryLabel(String value) {
  switch (value) {
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

String _priorityLabel(String value) {
  switch (value) {
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

String _messageFromErrorCode(String code) {
  final normalized = code.trim().toUpperCase();

  switch (normalized) {
    case 'ATTACHMENT_TOO_LARGE':
      return 'support_ticket.error_attachment_too_large';
    case 'SUBJECT_REQUIRED':
      return 'support_ticket.error_subject_required';
    case 'MESSAGE_REQUIRED':
      return 'support_ticket.error_message_required';
    default:
      return 'support_ticket.create_error';
  }
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }

  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }

  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}
