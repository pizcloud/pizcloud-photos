import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

class ShareDialog extends StatelessWidget {
  const ShareDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformAlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PlatformCircularProgressIndicator(),
          Container(margin: const EdgeInsets.only(top: 12), child: const Text('share_dialog_preparing').tr()),
        ],
      ),
    );
  }
}
