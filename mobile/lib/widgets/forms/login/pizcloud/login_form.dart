import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/models/pizcloud/saved_login_account.model.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/repositories/local_files_manager.repository.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/immich_title_text.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/common/pizcloud/pizcloud_logo.dart';
import 'package:immich_mobile/widgets/forms/login/loading_icon.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:immich_mobile/services/api.service.dart';

import 'package:immich_mobile/services/pizcloud/google.service.dart';
import 'package:immich_mobile/services/pizcloud/login_with_email.service.dart';
import 'package:immich_mobile/services/pizcloud/saved_login_accounts.service.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginForm extends HookConsumerWidget {
  LoginForm({super.key});

  final log = Logger('LoginForm');
  // final TextEditingController _emailController = TextEditingController();
  // final isBootstrapping = useState<bool>(false);
  // final lastBootstrapFailed = useState<bool>(false);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailController = useTextEditingController();
    // final isBootstrapping = useState<bool>(false);
    // final lastBootstrapFailed = useState<bool>(false);
    final loginFormKey = useMemoized(GlobalKey<FormState>.new);

    final isLoading = useState<bool>(false);
    final isLoadingServer = useState<bool>(false);
    // final logoAnimationController = useAnimationController(duration: const Duration(seconds: 60))..repeat();
    final warningMessage = useState<String?>(null);
    final savedAccounts = useState<List<SavedLoginAccount>>([]);
    final showEmailInput = useState<bool>(false);
    const savedAccountsService = SavedLoginAccountsService();

    // Validation states
    // focus & busy states for login actions
    final emailFocusNode = useFocusNode();
    final isEmailBusy = useState<bool>(false);
    final isGoogleBusy = useState<bool>(false);
    final emailSubmitted = useState<bool>(false);

    final bool isAnyBusy = isLoadingServer.value || isEmailBusy.value || isGoogleBusy.value;

    final GoogleService googleService = GoogleService();
    final LoginWithEmailService loginWithEmailService = LoginWithEmailService();

    useEffect(() {
      final accounts = savedAccountsService.load();
      savedAccounts.value = accounts;
      showEmailInput.value = accounts.isEmpty;
      return null;
    }, const []);

    // Future<bool> waitForAccessTokenReady() async {
    //   const retries = 20;
    //   const delay = Duration(milliseconds: 100);
    //   for (var i = 0; i < retries; i++) {
    //     final token = Store.tryGet(StoreKey.accessToken);
    //     debugPrint('token: $token');
    //     if (token != null && token.isNotEmpty) {
    //       return true;
    //     }
    //     await Future<void>.delayed(delay);
    //   }
    //   return false;
    // }

    Future<void> handleSyncFlow() async {
      final backgroundManager = ref.read(backgroundSyncProvider);
      await backgroundManager.cancel();
      await backgroundManager.syncLocal(full: true);
      await backgroundManager.syncRemote();
      await backgroundManager.hashAssets();

      if (Store.get(StoreKey.syncAlbums, false)) {
        await backgroundManager.syncLinkedAlbum();
      }
    }

    getManageMediaPermission() async {
      final hasPermission = await ref.read(localFilesManagerRepositoryProvider).hasManageMediaPermission();
      if (!hasPermission) {
        await showPlatformDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
              elevation: 5,
              title: Text(
                'manage_media_access_title',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.primaryColor),
              ).tr(),
              content: SingleChildScrollView(
                child: ListBody(
                  children: [
                    const Text('manage_media_access_subtitle', style: TextStyle(fontSize: 14)).tr(),
                    const SizedBox(height: 4),
                    const Text('manage_media_access_rationale', style: TextStyle(fontSize: 12)).tr(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'cancel'.tr(),
                    style: TextStyle(fontWeight: FontWeight.w600, color: context.primaryColor),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(localFilesManagerRepositoryProvider).requestManageMediaPermission();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'manage_media_access_settings'.tr(),
                    style: TextStyle(fontWeight: FontWeight.w600, color: context.primaryColor),
                  ),
                ),
              ],
            );
          },
        );
      }
    }

    bool isSyncRemoteDeletionsMode() => Platform.isAndroid && Store.get(StoreKey.manageLocalMediaAndroid, false);

    String? validateEmail(String? value) {
      final email = (value ?? '').trim();
      if (email.isEmpty) return 'Please enter your email';

      final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
      if (!emailRegex.hasMatch(email)) {
        return 'Enter a valid email address';
      }
      return null;
    }

    // =================NEW======================
    Future<void> onGoogleLogin() async {
      if (isGoogleBusy.value || isAnyBusy) return;

      isGoogleBusy.value = true;
      try {
        final result = await googleService.logInWithGoogle(ref: ref);

        if (result.authSaved != true) {
          ImmichToast.show(
            context: context,
            msg: "login_form_server_error".tr(),
            toastType: ToastType.error,
            gravity: ToastGravity.TOP,
          );
          return;
        }

        // Follow the same post-login flow as OAuth/password login
        final permission = ref.watch(galleryPermissionNotifier);
        final isBeta = Store.isBetaTimelineEnabled;
        if (isBeta) {
          await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();
          if (isSyncRemoteDeletionsMode()) {
            await getManageMediaPermission();
          }
          // await waitForAccessTokenReady();
          unawaited(handleSyncFlow());
          ref.read(websocketProvider.notifier).connect();
          unawaited(context.replaceRoute(const TabShellRoute()));
          return;
        }
        if (permission.isGranted || permission.isLimited) {
          unawaited(ref.watch(backupProvider.notifier).resumeBackup());
        }
        unawaited(context.replaceRoute(const TabControllerRoute()));
      } on GoogleSignInException catch (e) {
        final code = e.code.name.toLowerCase();
        if (code.contains('cancel')) return;
        if (!context.mounted) return;
      } catch (e) {
        if (!context.mounted) return;
        ImmichToast.show(
          context: context,
          msg: 'login_form_server_error'.tr(),
          toastType: ToastType.error,
          gravity: ToastGravity.TOP,
        );
      } finally {
        if (context.mounted) isGoogleBusy.value = false;
      }
    }

    Future<void> continueWithEmail() async {
      if (isEmailBusy.value || isAnyBusy) return;

      emailSubmitted.value = true;
      final isValid = loginFormKey.currentState?.validate() ?? false;
      if (!isValid) {
        emailFocusNode.requestFocus();
        return;
      }

      final email = emailController.text.trim();
      FocusScope.of(context).unfocus();

      isEmailBusy.value = true;
      try {
        final result = await loginWithEmailService.authenticate(email, ref);

        // if (!context.mounted) return;
        if (result.authSaved != true) {
          ImmichToast.show(
            context: context,
            msg: "login_form_server_error".tr(),
            toastType: ToastType.error,
            gravity: ToastGravity.TOP,
          );
          return;
        }
        // Follow the same post-login flow as OAuth/password login
        final permission = ref.watch(galleryPermissionNotifier);
        final isBeta = Store.isBetaTimelineEnabled;
        if (isBeta) {
          await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();
          if (isSyncRemoteDeletionsMode()) {
            await getManageMediaPermission();
          }
          // await waitForAccessTokenReady();
          unawaited(handleSyncFlow());
          ref.read(websocketProvider.notifier).connect();
          unawaited(context.replaceRoute(const TabShellRoute()));
          return;
        }
        if (permission.isGranted || permission.isLimited) {
          unawaited(ref.watch(backupProvider.notifier).resumeBackup());
        }
        unawaited(context.replaceRoute(const TabControllerRoute()));
      } on PlatformException catch (e) {
        if (!context.mounted) return;
      } catch (e) {
        if (!context.mounted) return;
        ImmichToast.show(
          context: context,
          msg: 'login_form_server_error'.tr(),
          toastType: ToastType.error,
          gravity: ToastGravity.TOP,
        );
      } finally {
        if (context.mounted) {
          isEmailBusy.value = false;
        }
      }
    }

    void updateSavedAccounts(List<SavedLoginAccount> accounts) {
      savedAccounts.value = accounts;
      if (accounts.isEmpty) {
        showEmailInput.value = true;
      }
    }

    Widget buildSavedAccountAvatar(SavedLoginAccount account) {
      final avatarColor = account.avatarColor.toColor();
      final displayChar = (account.name.isNotEmpty ? account.name : account.email)[0].toUpperCase();
      final endpoint = Store.tryGet(StoreKey.serverEndpoint);
      final profileImageUrl = (endpoint != null && endpoint.isNotEmpty)
          ? '$endpoint/users/${account.userId}/profile-image?d=${account.profileChangedAt.millisecondsSinceEpoch}'
          : null;

      final textIcon = DefaultTextStyle(
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: avatarColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
        ),
        child: Text(displayChar),
      );

      return CircleAvatar(
        backgroundColor: avatarColor,
        radius: 18,
        child: account.hasProfileImage && profileImageUrl != null
            ? ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(50)),
                child: CachedNetworkImage(
                  fit: BoxFit.cover,
                  cacheKey: '${account.userId}-${account.profileChangedAt.toIso8601String()}',
                  width: 36,
                  height: 36,
                  placeholder: (_, __) => const SizedBox.shrink(),
                  imageUrl: profileImageUrl,
                  httpHeaders: ApiService.getRequestHeaders(),
                  fadeInDuration: const Duration(milliseconds: 300),
                  errorWidget: (context, error, stackTrace) => textIcon,
                ),
              )
            : textIcon,
      );
    }

    Widget buildSavedAccountRow(SavedLoginAccount account) {
      return InkWell(
        onTap: isAnyBusy
            ? null
            : () {
                emailController.text = account.email;
                continueWithEmail();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              buildSavedAccountAvatar(account),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name.isNotEmpty ? account.name : account.email,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(account.email, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.redAccent),
                onPressed: isAnyBusy
                    ? null
                    : () async {
                        final updated = await savedAccountsService.removeByEmail(account.email);
                        updateSavedAccounts(updated);
                      },
              ),
            ],
          ),
        ),
      );
    }

    Widget buildSavedAccountsSection() {
      if (savedAccounts.value.isEmpty) {
        return const SizedBox.shrink();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            'choose_account_to_continue',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ).tr(),
          const SizedBox(height: 8),
          // Builder(
          //   builder: (context) {
          //     const rowHeight = 80.0;
          //     const maxListHeight = 220.0;
          //     final listHeight = (savedAccounts.value.length * rowHeight).clamp(0.0, maxListHeight);
          //     final shouldScroll = savedAccounts.value.length * rowHeight > maxListHeight;
          //
          //     return SizedBox(
          //       height: listHeight,
          //       child: Scrollbar(
          //         child: ListView.builder(
          //           physics: shouldScroll
          //               ? const AlwaysScrollableScrollPhysics()
          //               : const NeverScrollableScrollPhysics(),
          //           itemCount: savedAccounts.value.length,
          //           itemBuilder: (context, index) => buildSavedAccountRow(savedAccounts.value[index]),
          //         ),
          //       ),
          //     );
          //   },
          // ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: Scrollbar(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: () {
                  const rowHeightEstimate = 80.0;
                  const maxListHeight = 220.0;
                  final shouldScroll =
                      savedAccounts.value.length > 3 ||
                      (savedAccounts.value.length * rowHeightEstimate) > maxListHeight;
                  return shouldScroll ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics();
                }(),
                itemCount: savedAccounts.value.length,
                itemBuilder: (context, index) => buildSavedAccountRow(savedAccounts.value[index]),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: isAnyBusy
                  ? null
                  : () {
                      // emailController.text = emailController.text;
                      emailController.clear();
                      showEmailInput.value = true;
                      Future.microtask(() => emailFocusNode.requestFocus());
                    },
              child: const Text('use_another_account').tr(),
            ),
          ),
        ],
      );
    }

    buildVersionCompatWarning() {
      if (warningMessage.value == null) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.isDarkTheme ? Colors.red.shade700 : Colors.red.shade100,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            border: Border.all(color: context.isDarkTheme ? Colors.red.shade900 : Colors.red[200]!),
          ),
          child: Text(warningMessage.value!, textAlign: TextAlign.center),
        ),
      );
    }

    buildLogin() {
      return AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildVersionCompatWarning(),
            isLoading.value
                ? const LoadingIcon()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [const Text("log_in_or_sign_up", style: TextStyle(fontSize: 24)).tr()],
                      ),
                      const SizedBox(height: 18),

                      ElevatedButton.icon(
                        icon: isGoogleBusy.value
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.login),
                        label: Text(isGoogleBusy.value ? 'please_wait'.tr() : 'continue_with_google'.tr()),
                        onPressed: isAnyBusy ? null : () => onGoogleLogin(),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          children: [
                            const Expanded(child: Divider()),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Text('or_login_type', style: Theme.of(context).textTheme.labelMedium).tr(),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        // child: Divider(color: context.isDarkTheme ? Colors.white : Colors.black),
                      ),

                      const SizedBox(height: 16),
                      buildSavedAccountsSection(),
                      if (showEmailInput.value) ...[
                        TextFormField(
                          controller: emailController,
                          focusNode: emailFocusNode,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            hintText: 'you@example.com',
                            suffixIcon: emailController.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: isAnyBusy
                                        ? null
                                        : () {
                                            emailController.clear();
                                          },
                                    icon: const Icon(Icons.clear),
                                  ),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.done,
                          enabled: !isAnyBusy,
                          validator: validateEmail,
                          onFieldSubmitted: (_) => continueWithEmail(),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: isAnyBusy ? null : continueWithEmail,
                          icon: isEmailBusy.value
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.arrow_forward),
                          label: Text(isEmailBusy.value ? 'please_wait'.tr() : 'continue'.tr()),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: Theme.of(context).textTheme.bodySmall,
                            children: [
                              TextSpan(text: 'auth_agreement_prefix'.tr()),
                              TextSpan(
                                text: 'auth_terms_of_service'.tr(),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    Future.microtask(() {
                                      launchUrl(
                                        Uri.parse('https://pizcloud.com/en/terms/'),
                                        mode: LaunchMode.externalApplication,
                                      );
                                    });
                                  },
                              ),
                              TextSpan(text: 'auth_agreement_and'.tr()),
                              TextSpan(
                                text: 'auth_privacy_policy'.tr(),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    Future.microtask(() {
                                      launchUrl(
                                        Uri.parse('https://pizcloud.com/en/privacy/'),
                                        mode: LaunchMode.externalApplication,
                                      );
                                    });
                                  },
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                      ),
                      // const SizedBox(height: 12),
                      // Row(
                      //   mainAxisAlignment: MainAxisAlignment.center,
                      //   children: [
                      //     const Text("no_account_yet").tr(),
                      //     TextButton(
                      //       onPressed: () => context.pushRoute(const SignupRoute()),
                      //       child: const Text("sign_up").tr(),
                      //     ),
                      //   ],
                      // ),
                    ],
                  ),
          ],
        ),
      );
    }

    // pizcloud: no manual server selection; login is always shown.
    Widget serverSelectionOrLogin = buildLogin();

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: constraints.maxHeight / 9),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        child: const PizCloudLogo(heroTag: 'logo'),
                        // child: RotationTransition(
                        //   turns: logoAnimationController,
                        //   child: const PizCloudLogo(heroTag: 'logo'),
                        // ),
                      ),
                      const Padding(padding: EdgeInsets.only(top: 8.0, bottom: 16), child: ImmichTitleText()),
                    ],
                  ),

                  Form(
                    key: loginFormKey,
                    autovalidateMode: emailSubmitted.value
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    child: serverSelectionOrLogin,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
