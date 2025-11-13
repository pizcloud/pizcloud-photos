import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../providers/media_permission.provider.dart';

class MediaPermissionLifecycleListener extends ConsumerStatefulWidget {
  const MediaPermissionLifecycleListener({super.key});
  @override
  ConsumerState<MediaPermissionLifecycleListener> createState() => _MediaPermissionLifecycleListenerState();
}

class _MediaPermissionLifecycleListenerState extends ConsumerState<MediaPermissionLifecycleListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(mediaPermissionProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
