import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/models/backup/backup_state.model.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/cast.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/asset_viewer/cast_dialog.dart';
import 'package:immich_mobile/widgets/common/app_bar_dialog/app_bar_dialog.dart';
import 'package:immich_mobile/widgets/common/user_circle_avatar.dart';
import 'package:flutter/foundation.dart';

class ImmichAppBar extends ConsumerWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  final List<Widget>? actions;
  final bool showUploadButton;

  const ImmichAppBar({super.key, this.actions, this.showUploadButton = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BackUpState backupState = ref.watch(backupProvider);
    final bool isEnableAutoBackup = backupState.backgroundBackup || backupState.autoBackup;
    final user = ref.watch(currentUserProvider);
    final bool versionWarningPresent = ref.watch(versionWarningPresentProvider(user));
    final isDarkTheme = context.isDarkTheme;
    const widgetSize = 30.0;
    final isCasting = ref.watch(castProvider.select((c) => c.isCasting));

    buildProfileIndicator() {
      return InkWell(
        onTap: () =>
            showPlatformDialog(
              context: context,
              useRootNavigator: false,
              builder: (ctx) => const ImmichAppBarDialog(),
            ),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Badge(
          label: Container(
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(widgetSize / 2)),
            child: Icon(
              context.platformIcon(material: Icons.info, cupertino: CupertinoIcons.info),
              color: const Color.fromARGB(255, 243, 188, 106),
              size: widgetSize / 2,
            ),
          ),
          backgroundColor: Colors.transparent,
          alignment: Alignment.bottomRight,
          isLabelVisible: versionWarningPresent,
          offset: const Offset(-2, -12),
          child: user == null
              ? Icon(
                  context.platformIcon(material: Icons.face_outlined, cupertino: CupertinoIcons.person_crop_circle),
                  size: widgetSize,
                )
              : Semantics(
                  label: "logged_in_as".tr(namedArgs: {"user": user.name}),
                  child: UserCircleAvatar(radius: 17, size: 31, user: user),
                ),
        ),
      );
    }

    getBackupBadgeIcon() {
      final iconColor = isDarkTheme ? Colors.white : Colors.black;

      if (isEnableAutoBackup) {
        if (backupState.backupProgress == BackUpProgressEnum.inProgress) {
          return Container(
            padding: const EdgeInsets.all(3.5),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(iconColor),
              semanticsLabel: 'backup_controller_page_backup'.tr(),
            ),
          );
        } else if (backupState.backupProgress != BackUpProgressEnum.inBackground &&
            backupState.backupProgress != BackUpProgressEnum.manualInProgress) {
          return Icon(
            context.platformIcons.checkMark,
            size: 9,
            color: iconColor,
            semanticLabel: 'backup_controller_page_backup'.tr(),
          );
        }
      }

      if (!isEnableAutoBackup) {
        return Icon(
          context.platformIcon(material: Icons.cloud_off_rounded, cupertino: CupertinoIcons.cloud),
          size: 9,
          color: iconColor,
          semanticLabel: 'backup_controller_page_backup'.tr(),
        );
      }
    }

    buildBackupIndicator() {
      final indicatorIcon = getBackupBadgeIcon();
      final badgeBackground = context.colorScheme.surfaceContainer;

      return InkWell(
        onTap: () => context.pushRoute(const BackupControllerRoute()),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Badge(
          label: Container(
            width: widgetSize / 2,
            height: widgetSize / 2,
            decoration: BoxDecoration(
              color: badgeBackground,
              border: Border.all(color: context.colorScheme.outline.withValues(alpha: .3)),
              borderRadius: BorderRadius.circular(widgetSize / 2),
            ),
            child: indicatorIcon,
          ),
          backgroundColor: Colors.transparent,
          alignment: Alignment.bottomRight,
          isLabelVisible: indicatorIcon != null,
          offset: const Offset(-2, -12),
          child: Icon(
            context.platformIcon(material: Icons.backup_rounded, cupertino: CupertinoIcons.cloud_upload),
            size: widgetSize,
            color: context.primaryColor,
          ),
        ),
      );
    }

    return PlatformAppBar(
      backgroundColor: context.themeData.appBarTheme.backgroundColor,
      automaticallyImplyLeading: false,
      title: Builder(
        builder: (BuildContext context) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3.0),
                child: SvgPicture.asset(
                  context.isDarkTheme
                      ? 'assets/pizcloud-logo-inline-dark.svg'
                      : 'assets/pizcloud-logo-inline-light.svg', // pizcloud
                  height: 40,
                ),
              ),
              Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                showDuration: Duration(seconds: 4),
                message:
                    "The old timeline is deprecated and will be removed in a future release. Kindly switch to the new timeline under Advanced Settings.",
                child: Padding(
                  padding: const EdgeInsets.only(top: 3.0),
                  child: Icon(
                    context.platformIcon(material: Icons.error_rounded, cupertino: CupertinoIcons.exclamationmark_triangle),
                    fill: 1,
                    color: Colors.amber,
                    size: 20,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      cupertino: (_, __) => CupertinoNavigationBarData(
        transitionBetweenRoutes: false,
        padding: const EdgeInsetsDirectional.only(start: 12, end: 12),
        backgroundColor: context.colorScheme.surface.withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(color: context.colorScheme.outline.withValues(alpha: 0.2)),
        ),
      ),
      material: (_, __) => MaterialAppBarData(
      ),
      trailingActions: [
        if (actions != null)
          ...actions!.map((action) => Padding(padding: const EdgeInsets.only(right: 16), child: action)),
        if (kDebugMode || kProfileMode)
          IconButton(
            icon: Icon(context.platformIcon(material: Icons.science_rounded, cupertino: CupertinoIcons.lab_flask)),
            onPressed: () => context.pushRoute(const FeatInDevRoute()),
          ),
        if (isCasting)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              onPressed: () {
                showPlatformDialog(context: context, builder: (context) => const CastDialog());
              },
              icon: Icon(
                context.platformIcon(
                  material: isCasting ? Icons.cast_connected_rounded : Icons.cast_rounded,
                  cupertino: CupertinoIcons.tv,
                ),
              ),
            ),
          ),
        if (showUploadButton) Padding(padding: const EdgeInsets.only(right: 20), child: buildBackupIndicator()),
        Padding(padding: const EdgeInsets.only(right: 20), child: buildProfileIndicator()),
      ],
    );
  }
}
