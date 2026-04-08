import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/sessions.provider.dart';
import 'package:immich_mobile/widgets/common/confirm_dialog.dart';
import 'package:immich_mobile/widgets/common/scaffold_error_body.dart';
import 'package:openapi/api.dart';

@RoutePage()
class AuthorizedDevicesPage extends ConsumerWidget {
  const AuthorizedDevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(deviceSessionsProvider);

    if (sessionState.isLoading && sessionState.sessions.isEmpty) {
      return PlatformScaffold(
        appBar: PlatformAppBar(
          title: const Text('authorized_devices').tr(),
          material: (_, __) => MaterialAppBarData(centerTitle: false),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (sessionState.errorMessage != null && sessionState.sessions.isEmpty) {
      return PlatformScaffold(
        appBar: PlatformAppBar(
          title: const Text('authorized_devices').tr(),
          material: (_, __) => MaterialAppBarData(centerTitle: false),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaffoldErrorBody(withIcon: true, errorMsg: sessionState.errorMessage),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.read(deviceSessionsProvider.notifier).load(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('retry').tr(),
              ),
            ],
          ),
        ),
      );
    }

    final currentSessions = sessionState.sessions.where((session) => session.current).toList(growable: false);
    final otherSessions = sessionState.sessions.where((session) => !session.current).toList(growable: false);

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('authorized_devices').tr(),
        material: (_, __) => MaterialAppBarData(centerTitle: false),
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: () => ref.read(deviceSessionsProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              'manage_your_devices'.tr(),
              style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
            if (sessionState.isRefreshing) ...[const SizedBox(height: 10), const LinearProgressIndicator(minHeight: 2)],
            const SizedBox(height: 14),
            if (currentSessions.isNotEmpty) ...[
              _SessionSectionTitle(title: 'current_device'.tr()),
              const SizedBox(height: 8),
              for (final session in currentSessions) ...[
                _SessionTile(session: session, isDeleting: false, canDelete: false, onDelete: null),
                const SizedBox(height: 10),
              ],
            ],
            _SessionSectionTitle(title: 'other_devices'.tr()),
            const SizedBox(height: 8),
            if (otherSessions.isEmpty)
              _EmptySessionState(message: 'no_devices'.tr())
            else ...[
              for (final session in otherSessions) ...[
                _SessionTile(
                  session: session,
                  isDeleting: sessionState.deletingSessionIds.contains(session.id),
                  canDelete: true,
                  onDelete: () => _onLogoutSession(context, ref, session),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: sessionState.isLoggingOutAll ? null : () => _onLogoutAllSessions(context, ref),
                  icon: sessionState.isLoggingOutAll
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(
                          context.platformIcon(
                            material: Icons.logout_rounded,
                            cupertino: CupertinoIcons.square_arrow_left,
                          ),
                        ),
                  label: const Text('log_out_all_devices').tr(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onLogoutSession(BuildContext context, WidgetRef ref, SessionResponseDto session) async {
    final confirm = await _confirmDialog(context, 'logout_this_device_confirmation');
    if (!confirm) {
      return;
    }

    final success = await ref.read(deviceSessionsProvider.notifier).logoutSession(session.id);
    if (!context.mounted) {
      return;
    }

    if (success) {
      context.scaffoldMessenger.showSnackBar(SnackBar(content: Text('logged_out_device'.tr())));
      return;
    }

    context.scaffoldMessenger.showSnackBar(SnackBar(content: Text('errors.unable_to_log_out_device'.tr())));
  }

  Future<void> _onLogoutAllSessions(BuildContext context, WidgetRef ref) async {
    final confirm = await _confirmDialog(context, 'logout_all_device_confirmation');
    if (!confirm) {
      return;
    }

    final success = await ref.read(deviceSessionsProvider.notifier).logoutAllOtherSessions();
    if (!context.mounted) {
      return;
    }

    if (success) {
      context.scaffoldMessenger.showSnackBar(SnackBar(content: Text('logged_out_all_devices'.tr())));
      return;
    }

    context.scaffoldMessenger.showSnackBar(SnackBar(content: Text('errors.unable_to_log_out_all_devices'.tr())));
  }

  Future<bool> _confirmDialog(BuildContext context, String contentKey) async {
    final confirmed = await showPlatformDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(title: 'log_out', content: contentKey, ok: 'yes', onOk: () {}),
    );

    return confirmed == true;
  }
}

class _SessionSectionTitle extends StatelessWidget {
  const _SessionSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: context.textTheme.labelMedium?.copyWith(
        color: context.colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.isDeleting,
    required this.canDelete,
    required this.onDelete,
  });

  final SessionResponseDto session;
  final bool isDeleting;
  final bool canDelete;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final appVersion = session.appVersion?.trim() ?? '';
    final subtitleChunks = <String>[
      session.deviceOS.trim().isEmpty ? 'unknown'.tr() : session.deviceOS.trim(),
      if (appVersion.isNotEmpty) 'v$appVersion',
    ];

    final updatedAt = DateTime.tryParse(session.updatedAt) ?? DateTime.tryParse(session.createdAt);
    final lastSeen = updatedAt == null
        ? '-'
        : DateFormat.yMMMd(context.locale.toString()).add_jm().format(updatedAt.toLocal());

    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: context.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        minLeadingWidth: 42,
        leading: Icon(
          context.platformIcon(material: Icons.devices_rounded, cupertino: CupertinoIcons.device_phone_portrait),
          color: context.colorScheme.primary,
        ),
        title: Text(_deviceName(session), style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${subtitleChunks.join(' • ')}\n${'last_seen'.tr()}: $lastSeen',
            style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ),
        isThreeLine: true,
        trailing: canDelete
            ? isDeleting
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      onPressed: onDelete,
                      tooltip: 'log_out'.tr(),
                      icon: Icon(
                        context.platformIcon(
                          material: Icons.logout_rounded,
                          cupertino: CupertinoIcons.square_arrow_left,
                        ),
                      ),
                    )
            : null,
      ),
    );
  }

  String _deviceName(SessionResponseDto session) {
    final raw = session.deviceType.trim();
    if (raw.isNotEmpty) {
      return raw;
    }
    return 'unknown'.tr();
  }
}

class _EmptySessionState extends StatelessWidget {
  const _EmptySessionState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: context.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
