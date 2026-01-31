import 'package:auto_route/auto_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/widgets/settings/beta_sync_settings/sync_status_and_actions.dart';

@RoutePage()
class SyncStatusPage extends StatelessWidget {
  const SyncStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text("sync_status").t(context: context),
        leading: IconButton(
          onPressed: () => context.maybePop(true),
          splashRadius: 24,
          icon: Icon(context.platformIcons.back),
        ),
        material: (_, __) => MaterialAppBarData(elevation: 0),
      ),
      body: const SyncStatusAndActions(),
    );
  }
}
