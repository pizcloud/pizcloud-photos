import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
// import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/pages/pizcloud/drift_partner_email_selection.page.dart'; // pizcloud
import 'package:immich_mobile/presentation/widgets/people/partner_user_avatar.widget.dart';
import 'package:immich_mobile/presentation/utils/partner_share_email.utils.dart'; // pizcloud
import 'package:immich_mobile/providers/infrastructure/partner.provider.dart';
import 'package:immich_mobile/providers/infrastructure/user.provider.dart';
import 'package:immich_mobile/providers/api.provider.dart'; // pizcloud
import 'package:immich_mobile/widgets/common/confirm_dialog.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

@RoutePage()
class DriftPartnerPage extends HookConsumerWidget {
  const DriftPartnerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // final potentialPartnersAsync = ref.watch(driftAvailablePartnerProvider); // pizcloud

    addNewUsersHandler() async {
      // pizcloud: email-based partner selection.
      final selectedEmails = await showPlatformDialog<List<String>>(
        context: context,
        builder: (context) => const Dialog(insetPadding: EdgeInsets.zero, child: DriftPartnerEmailSelectionPage()),
      );

      if (selectedEmails == null || selectedEmails.isEmpty) {
        return;
      }

      try {
        final apiService = ref.read(apiServiceProvider);
        final resolution = await resolvePartnerUserIdsByEmail(apiService: apiService, emails: selectedEmails);
        final existingPartners = await ref.read(driftSharedByPartnerProvider.future);
        final existingIds = {...existingPartners.map((partner) => partner.id)};
        final userIdsToAdd = resolution.userIds.where((id) => !existingIds.contains(id)).toList();

        if (resolution.missingEmails.isNotEmpty) {
          final preview = resolution.missingEmails.take(3).join(', ');
          final suffix = resolution.missingEmails.length > 3 ? '...' : '';
          ImmichToast.show(context: context, msg: 'Not found in Pizcloud: $preview$suffix', toastType: ToastType.info);
        }

        if (userIdsToAdd.isEmpty) {
          ImmichToast.show(
            context: context,
            msg: 'No new users to add from selected emails.',
            toastType: ToastType.info,
          );
          return;
        }

        await ref.read(partnerUsersProvider.notifier).addPartnersById(userIdsToAdd);
      } catch (_) {
        ImmichToast.show(context: context, msg: "partner_page_partner_add_failed".tr(), toastType: ToastType.error);
      }
      // Old flow: show all users and select from the system list.
      // final potentialPartners = potentialPartnersAsync.value;
      // if (potentialPartners == null || potentialPartners.isEmpty) {
      //   ImmichToast.show(context: context, msg: "partner_page_no_more_users".tr());
      //   return;
      // }
      // final selectedUser = await showPlatformDialog<PartnerUserDto>(
      //   context: context,
      //   builder: (context) {
      //     return SimpleDialog(
      //       title: const Text("partner_page_select_partner").tr(),
      //       children: [
      //         for (PartnerUserDto partner in potentialPartners)
      //           SimpleDialogOption(
      //             onPressed: () => context.pop(partner),
      //             child: Row(
      //               children: [
      //                 Padding(
      //                   padding: const EdgeInsets.only(right: 8),
      //                   child: PartnerUserAvatar(partner: partner),
      //                 ),
      //                 Text(partner.name),
      //               ],
      //             ),
      //           ),
      //       ],
      //     );
      //   },
      // );
      // if (selectedUser != null) {
      //   await ref.read(partnerUsersProvider.notifier).addPartner(selectedUser);
      // }
      // #pizcloud
    }

    onDeleteUser(PartnerUserDto partner) {
      return showPlatformDialog(
        context: context,
        builder: (BuildContext context) {
          return ConfirmDialog(
            title: "stop_photo_sharing",
            content: "partner_page_stop_sharing_content".tr(namedArgs: {'partner': partner.name}),
            onOk: () => ref.read(partnerUsersProvider.notifier).removePartner(partner),
          );
        },
      );
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text("partners").t(context: context),
        trailingActions: [
          IconButton(
            // onPressed: potentialPartnersAsync.whenOrNull(data: (data) => addNewUsersHandler), // pizcloud
            onPressed: addNewUsersHandler, // pizcloud
            icon: Icon(context.platformIcon(material: Icons.person_add, cupertino: CupertinoIcons.person_add)),
            tooltip: "add_partner".tr(),
          ),
        ],
        material: (_, __) => MaterialAppBarData(elevation: 0, centerTitle: false),
      ),
      body: _SharedToPartnerList(onAddPartner: addNewUsersHandler, onDeletePartner: onDeleteUser),
    );
  }
}

class _SharedToPartnerList extends ConsumerWidget {
  final VoidCallback onAddPartner;
  final Function(PartnerUserDto partner) onDeletePartner;

  const _SharedToPartnerList({required this.onAddPartner, required this.onDeletePartner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerAsync = ref.watch(driftSharedByPartnerProvider);

    return partnerAsync.when(
      data: (partners) {
        if (partners.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: const Text("partner_page_empty_message", style: TextStyle(fontSize: 14)).tr(),
                ),
                Align(
                  alignment: Alignment.center,
                  child: ElevatedButton.icon(
                    onPressed: onAddPartner,
                    icon: Icon(context.platformIcon(material: Icons.person_add, cupertino: CupertinoIcons.person_add)),
                    label: const Text("add_partner").tr(),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: partners.length,
          itemBuilder: (context, index) {
            final partner = partners[index];
            return ListTile(
              leading: PartnerUserAvatar(partner: partner),
              title: Text(partner.name),
              subtitle: Text(partner.email),
              trailing: IconButton(
                icon: Icon(
                  context.platformIcon(material: Icons.person_remove, cupertino: CupertinoIcons.person_crop_circle_badge_minus),
                ),
                onPressed: () => onDeletePartner(partner),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('error_loading_partners'.tr(args: [error.toString()]))),
    );
  }
}
