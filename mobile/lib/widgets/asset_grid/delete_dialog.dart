import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/widgets/common/confirm_dialog.dart';

class DeleteDialog extends ConfirmDialog {
  const DeleteDialog({super.key, String? alert, required Function onDelete})
    : super(
        title: "delete_dialog_title",
        content: alert ?? "delete_dialog_alert",
        cancel: "cancel",
        ok: "delete",
        onOk: onDelete,
      );
}

class DeleteLocalOnlyDialog extends StatelessWidget {
  final void Function(bool onlyMerged) onDeleteLocal;

  const DeleteLocalOnlyDialog({super.key, required this.onDeleteLocal});

  @override
  Widget build(BuildContext context) {
    void onDeleteBackedUpOnly() {
      context.pop(true);
      onDeleteLocal(true);
    }

    void onForceDelete() {
      context.pop(false);
      onDeleteLocal(false);
    }

    return PlatformAlertDialog(
      title: const Text("delete_dialog_title").tr(),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("delete_dialog_alert_local_non_backed_up").tr(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: PlatformElevatedButton(
              onPressed: () => context.pop(),
              material: (_, __) => MaterialElevatedButtonData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colorScheme.surfaceDim,
                  foregroundColor: context.primaryColor,
                ),
              ),
              child: const Text("cancel", style: TextStyle(fontWeight: FontWeight.bold)).tr(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: PlatformElevatedButton(
              onPressed: onDeleteBackedUpOnly,
              material: (_, __) => MaterialElevatedButtonData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colorScheme.errorContainer,
                  foregroundColor: context.colorScheme.onErrorContainer,
                ),
              ),
              child: const Text(
                "delete_local_dialog_ok_backed_up_only",
                style: TextStyle(fontWeight: FontWeight.bold),
              ).tr(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: PlatformElevatedButton(
              onPressed: onForceDelete,
              material: (_, __) => MaterialElevatedButtonData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[400],
                  foregroundColor: Colors.white,
                ),
              ),
              cupertino: (_, __) => CupertinoElevatedButtonData(
                color: Colors.red[400],
              ),
              child: const Text("delete_local_dialog_ok_force", style: TextStyle(fontWeight: FontWeight.bold)).tr(),
            ),
          ),
        ],
      ),
      material: (_, __) => MaterialAlertDialogData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
    );
  }
}
