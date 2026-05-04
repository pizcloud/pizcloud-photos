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
      content: const Text("delete_dialog_alert_local_non_backed_up").tr(),
      actions: <Widget>[
        PlatformDialogAction(onPressed: () => context.pop(), child: const Text("cancel").tr()),
        PlatformDialogAction(
          onPressed: onDeleteBackedUpOnly,
          child: const Text("delete_local_dialog_ok_backed_up_only").tr(),
        ),
        PlatformDialogAction(
          onPressed: onForceDelete,
          cupertino: (_, __) => CupertinoDialogActionData(isDestructiveAction: true),
          child: Text("delete_local_dialog_ok_force", style: TextStyle(color: context.colorScheme.error)).tr(),
        ),
      ],
      material: (_, __) => MaterialAlertDialogData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
    );
  }
}
