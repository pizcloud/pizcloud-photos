import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/config/app_config.dart'; // pizcloud
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/models/backup/backup_state.model.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/backup/manual_upload.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/locale_provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/bytes_units.dart';
import 'package:immich_mobile/widgets/common/app_bar_dialog/app_bar_profile_info.dart';
import 'package:immich_mobile/widgets/common/confirm_dialog.dart';
import 'package:immich_mobile/services/pizcloud/account_api.service.dart'; // pizcloud
import 'package:immich_mobile/services/pizcloud/google.service.dart'; // pizcloud
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart'; // pizcloud
import 'package:url_launcher/url_launcher.dart';

@RoutePage()
class SettingsTabPage extends HookConsumerWidget {
  const SettingsTabPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    BackUpState backupState = ref.watch(backupProvider);
    final theme = context.themeData;
    final user = ref.watch(currentUserProvider);
    final isLoggingOut = useState(false);
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);
    final AccountApi accountApiService = AccountApi(); // pizcloud

    useEffect(() {
      ref.read(backupProvider.notifier).updateDiskInfo();
      ref.read(currentUserProvider.notifier).refresh();
      return null;
    }, []);

    Widget buildActionButton(IconData icon, String text, VoidCallback onTap, {Widget? trailing}) {
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.standard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 30),
        minLeadingWidth: 40,
        leading: SizedBox(child: Icon(icon, color: theme.textTheme.labelLarge?.color?.withAlpha(250), size: 20)),
        title: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(color: theme.textTheme.labelLarge?.color?.withAlpha(250)),
        ).tr(),
        onTap: onTap,
        trailing: trailing,
      );
    }

    Widget buildSettingButton() {
      return buildActionButton(
        context.platformIcon(material: Icons.settings_outlined, cupertino: CupertinoIcons.settings),
        "system_settings",
        () => context.pushRoute(const SettingsRoute()),
      );
    }

    // pizcloud
    Widget buildManageAccountButton() {
      return buildActionButton(
        context.platformIcon(
          material: Icons.manage_accounts,
          cupertino: CupertinoIcons.person_crop_circle_badge_checkmark,
        ),
        "manage_account",
        () async {
          try {
            final loginMethod = Store.tryGet(StoreKey.pizcloudLoginMethod);
            final baseUri = Uri.https(AppConfig.accountHost, '');

            String? extractSsoToken(dynamic data) {
              if (data is Map<String, dynamic>) {
                final token = data['sso_token'];
                if (token is String && token.isNotEmpty) return token;
              }
              return null;
            }

            if (loginMethod == 'google') {
              final googleService = GoogleService();
              var account = await googleService.attemptLightweightAuthentication();
              account ??= await googleService.signIn();
              final auth = account.authentication;
              final idToken = auth.idToken;
              if (idToken != null && idToken.isNotEmpty) {
                final verifyResponse = await accountApiService.verifyIdToken(idToken);
                final ssoToken = extractSsoToken(verifyResponse.data);
                if (ssoToken != null && ssoToken.isNotEmpty) {
                  final googleUri = Uri.https(AppConfig.accountHost, '/api/users/verify-sso-token', {
                    'sso_token': ssoToken,
                    'redirect': '/',
                  });
                  await FlutterWebAuth2.authenticate(
                    url: googleUri.toString(),
                    callbackUrlScheme: 'pizcloud',
                    options: const FlutterWebAuth2Options(),
                  );
                  return;
                }
              }
            }

            await FlutterWebAuth2.authenticate(
              url: baseUri.toString(),
              callbackUrlScheme: 'pizcloud',
              options: const FlutterWebAuth2Options(),
            );
          } catch (e, s) {
            debugPrint('Open manage account failed: $e');
            debugPrintStack(stackTrace: s);
          }
        },
      );
    }

    Widget buildReferralProgramButton() {
      return buildActionButton(
        context.platformIcon(material: Icons.wallet_giftcard, cupertino: CupertinoIcons.gift),
        "referral_program",
        () => context.pushRoute(ReferralRoute(userEmail: user?.email)),
      );
    }

    Widget buildDiscountCodeButton() {
      return buildActionButton(
        context.platformIcon(material: Icons.price_check, cupertino: CupertinoIcons.tag),
        "referral.discount_code",
        () => context.pushRoute(DiscountCodeRoute(userEmail: user?.email)),
      );
    }

    Future<void> removeServerCookies() async {
      await accountApiService.logout();
    }
    // #pizcloud

    Widget buildAppLogButton() {
      return buildActionButton(
        context.platformIcon(material: Icons.assignment_outlined, cupertino: CupertinoIcons.doc_text),
        "profile_drawer_app_logs",
        () => context.pushRoute(const AppLogRoute()),
      );
    }

    Widget buildSignOutButton() {
      return buildActionButton(
        context.platformIcon(material: Icons.logout_rounded, cupertino: CupertinoIcons.square_arrow_left),
        "sign_out",
        () async {
          if (isLoggingOut.value) {
            return;
          }

          unawaited(
            showPlatformDialog(
              context: context,
              builder: (BuildContext ctx) {
                return ConfirmDialog(
                  title: "app_bar_signout_dialog_title",
                  content: "app_bar_signout_dialog_content",
                  ok: "yes",
                  onOk: () async {
                    isLoggingOut.value = true;
                    await ref.read(authProvider.notifier).logout().whenComplete(() => isLoggingOut.value = false);

                    ref.read(manualUploadProvider.notifier).cancelBackup();
                    ref.read(backupProvider.notifier).cancelBackup();
                    unawaited(ref.read(assetProvider.notifier).clearAllAssets());
                    ref.read(websocketProvider.notifier).disconnect();
                    await removeServerCookies(); // pizcloud
                    unawaited(context.replaceRoute(const LoginRoute()));
                  },
                );
              },
            ),
          );
        },
        trailing: isLoggingOut.value
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : null,
      );
    }

    Widget buildStorageInformation() {
      var percentage = backupState.serverInfo.diskUsagePercentage / 100;
      var usedDiskSpace = backupState.serverInfo.diskUse;
      var totalDiskSpace = backupState.serverInfo.diskSize;

      if (user != null && user.hasQuota) {
        usedDiskSpace = formatBytes(user.quotaUsageInBytes);
        totalDiskSpace = formatBytes(user.quotaSizeInBytes);
        percentage = user.quotaUsageInBytes / user.quotaSizeInBytes;
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(color: context.colorScheme.surface),
          child: ListTile(
            minLeadingWidth: 50,
            leading: Icon(
              context.platformIcon(material: Icons.storage_rounded, cupertino: CupertinoIcons.folder),
              color: theme.primaryColor,
            ),
            title: Text(
              "backup_controller_page_server_storage",
              style: context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
            ).tr(),
            isThreeLine: true,
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: LinearProgressIndicator(
                      minHeight: 10.0,
                      value: percentage,
                      borderRadius: const BorderRadius.all(Radius.circular(10.0)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: const Text(
                      'backup_controller_page_storage_format',
                    ).tr(namedArgs: {'used': usedDiskSpace, 'total': totalDiskSpace}),
                  ),
                  // pizcloud
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      icon: Icon(
                        context.platformIcon(
                          material: Icons.workspace_premium_rounded,
                          cupertino: CupertinoIcons.star_circle,
                        ),
                      ),
                      label: const Text('upgrade').tr(),
                      onPressed: () {
                        context.pushRoute(const BillingRoute());
                      },
                    ),
                  ),
                  // #pizcloud
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget buildFooter() {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // pizcloud
            InkWell(
              onTap: () {
                launchUrl(Uri.parse('https://pizcloud.com/en/terms/'), mode: LaunchMode.externalApplication);
              },
              child: Text("terms", style: context.textTheme.bodySmall).tr(),
            ),
            const SizedBox(width: 20, child: Text("•", textAlign: TextAlign.center)),
            InkWell(
              onTap: () {
                launchUrl(Uri.parse('https://pizcloud.com/en/privacy/'), mode: LaunchMode.externalApplication);
              },
              child: Text("policy", style: context.textTheme.bodySmall).tr(),
            ),
            // #pizcloud
          ],
        ),
      );
    }

    Widget buildReadonlyMessage() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.standard,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          minLeadingWidth: 20,
          tileColor: theme.primaryColor.withAlpha(80),
          title: Text(
            "profile_drawer_readonly_mode",
            style: theme.textTheme.labelLarge?.copyWith(color: theme.textTheme.labelLarge?.color?.withAlpha(250)),
            textAlign: TextAlign.center,
          ).tr(),
        ),
      );
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('settings').tr(),
        material: (_, __) => MaterialAppBarData(centerTitle: false),
      ),
      body: SafeArea(
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(top: 10.0, bottom: 16),
          children: [
            const AppBarProfileInfoBox(),
            buildStorageInformation(),
            if (Store.isBetaTimelineEnabled && isReadonlyModeEnabled) buildReadonlyMessage(),
            if (kDebugMode || kProfileMode) buildAppLogButton(), // pizcloud
            buildReferralProgramButton(), // pizcloud
            buildDiscountCodeButton(), // pizcloud
            buildManageAccountButton(), // pizcloud
            buildSettingButton(),
            // buildSignOutButton(),
            // buildFooter(),
          ],
        ),
      ),
    );
  }
}
