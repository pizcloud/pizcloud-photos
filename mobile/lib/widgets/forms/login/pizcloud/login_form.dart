import 'dart:async';
// import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
// import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
// import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/repositories/local_files_manager.repository.dart';
import 'package:immich_mobile/routing/router.dart';
// import 'package:immich_mobile/utils/url_helper.dart';
// import 'package:immich_mobile/utils/version_compatibility.dart';
import 'package:immich_mobile/widgets/common/immich_title_text.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/common/pizcloud/pizcloud_logo.dart';
import 'package:immich_mobile/widgets/forms/login/loading_icon.dart';
// import 'package:immich_mobile/widgets/forms/login/server_endpoint_input.dart';
import 'package:logging/logging.dart';
// import 'package:openapi/api.dart';
// import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';

import 'package:immich_mobile/services/pizcloud/google.service.dart';
import 'package:immich_mobile/services/pizcloud/login_with_email.service.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginForm extends HookConsumerWidget {
  LoginForm({super.key});

  final log = Logger('LoginForm');
  final TextEditingController _emailController = TextEditingController();
  // pizcloud: bootstrap state
  final isBootstrapping = useState<bool>(false);
  final lastBootstrapFailed = useState<bool>(false);

  // #pizcloud

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = useState<bool>(false);
    final isLoadingServer = useState<bool>(false);
    final logoAnimationController = useAnimationController(duration: const Duration(seconds: 60))..repeat();
    // final serverInfo = ref.watch(serverInfoProvider);
    final warningMessage = useState<String?>(null);
    final loginFormKey = GlobalKey<FormState>();

    // Validation states
    // focus & busy states for login actions
    final emailFocusNode = useFocusNode();
    final isEmailBusy = useState<bool>(false);
    final isGoogleBusy = useState<bool>(false);
    final emailSubmitted = useState<bool>(false);

    final bool isAnyBusy = isLoadingServer.value || isBootstrapping.value || isEmailBusy.value || isGoogleBusy.value;

    final GoogleService googleService = GoogleService();
    final LoginWithEmailService loginWithEmailService = LoginWithEmailService();
    // final GlobalKey<FormState> formKey = GlobalKey<FormState>();

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
        await showDialog(
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
            msg: "login_form_failed_login".tr(),
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
      } catch (e) {
        if (!context.mounted) return;
        ImmichToast.show(
          context: context,
          msg: 'login_form_failed_login'.tr(),
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

      final email = _emailController.text.trim();
      FocusScope.of(context).unfocus();

      isEmailBusy.value = true;
      try {
        final result = await loginWithEmailService.authenticate(email, ref);

        // if (!context.mounted) return;
        if (result.authSaved != true) {
          ImmichToast.show(
            context: context,
            msg: "login_form_failed_login".tr(),
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
        // final msg = (e.message?.isNotEmpty ?? false) ? e.message! : 'login_form_failed_login'.tr();
        // ImmichToast.show(context: context, msg: msg, toastType: ToastType.error, gravity: ToastGravity.TOP);
      } catch (e) {
        if (!context.mounted) return;
        ImmichToast.show(
          context: context,
          msg: 'login_form_failed_login'.tr(),
          toastType: ToastType.error,
          gravity: ToastGravity.TOP,
        );
      } finally {
        if (context.mounted) {
          isEmailBusy.value = false;
        }
      }
    }

    // =======================================
    // buildSelectServer() {
    //   const buttonRadius = 25.0;
    //   return Column(
    //     crossAxisAlignment: CrossAxisAlignment.stretch,
    //     children: [
    //       ServerEndpointInput(
    //         controller: serverEndpointController,
    //         focusNode: serverEndpointFocusNode,
    //         onSubmit: getServerAuthSettings,
    //       ),
    //       const SizedBox(height: 18),
    //       Row(
    //         children: [
    //           Expanded(
    //             child: ElevatedButton.icon(
    //               style: ElevatedButton.styleFrom(
    //                 padding: const EdgeInsets.symmetric(vertical: 12),
    //                 shape: const RoundedRectangleBorder(
    //                   borderRadius: BorderRadius.only(
    //                     topLeft: Radius.circular(buttonRadius),
    //                     bottomLeft: Radius.circular(buttonRadius),
    //                   ),
    //                 ),
    //               ),
    //               onPressed: () => context.pushRoute(const SettingsRoute()),
    //               icon: const Icon(Icons.settings_rounded),
    //               label: const Text(""),
    //             ),
    //           ),
    //           const SizedBox(width: 1),
    //           Expanded(
    //             flex: 3,
    //             child: ElevatedButton.icon(
    //               style: ElevatedButton.styleFrom(
    //                 padding: const EdgeInsets.symmetric(vertical: 12),
    //                 shape: const RoundedRectangleBorder(
    //                   borderRadius: BorderRadius.only(
    //                     topRight: Radius.circular(buttonRadius),
    //                     bottomRight: Radius.circular(buttonRadius),
    //                   ),
    //                 ),
    //               ),
    //               onPressed: isLoadingServer.value ? null : getServerAuthSettings,
    //               icon: const Icon(Icons.arrow_forward_rounded),
    //               label: const Text('next', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)).tr(),
    //             ),
    //           ),
    //         ],
    //       ),
    //       const SizedBox(height: 18),
    //       if (isLoadingServer.value) const LoadingIcon(),
    //     ],
    //   );
    // }

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
                      TextFormField(
                        controller: _emailController,
                        focusNode: emailFocusNode,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'you@example.com',
                          suffixIcon: _emailController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: isAnyBusy
                                      ? null
                                      : () {
                                          _emailController.clear();
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
            // if (!isOauthEnable.value && !isPasswordLoginEnable.value) Center(child: const Text('login_disabled').tr()),
            // const SizedBox(height: 12),
            // if (!AppConfig.lockServer)
            //   TextButton.icon(
            //     icon: const Icon(Icons.arrow_back),
            //     onPressed: (isAnyBusy || AppConfig.lockServer) ? null : () => serverEndpoint.value = null,
            //     label: const Text('back').tr(),
            //   ),
          ],
        ),
      );
    }

    // pizcloud: no manual server selection; login is always shown.
    Widget serverSelectionOrLogin = buildLogin();

    // Previous server selection flow (kept for reference).
    // final bool hasDefault = AppConfig.defaultServer.trim().isNotEmpty;
    // Widget serverSelectionOrLogin;
    //
    // if (serverEndpoint.value == null) {
    //   final isAutoMode = (getServerUrl() != null && getServerUrl()!.isNotEmpty) || (hasDefault && AppConfig.lockServer);
    //
    //   if (isAutoMode) {
    //     serverSelectionOrLogin = Column(
    //       crossAxisAlignment: CrossAxisAlignment.center,
    //       children: [
    //         if (isBootstrapping.value) const LoadingIcon(),
    //         if (!isBootstrapping.value && lastBootstrapFailed.value)
    //           ElevatedButton.icon(
    //             onPressed: isLoadingServer.value
    //                 ? null
    //                 : () async {
    //                     final stored = getServerUrl();
    //                     final fallback = AppConfig.defaultServer.trim();
    //                     final start = (stored != null && stored.isNotEmpty)
    //                         ? stored
    //                         : (fallback.isNotEmpty ? fallback : null);
    //                     if (start != null) {
    //                       await bootstrapWithUrl(start);
    //                     }
    //                   },
    //             icon: const Icon(Icons.refresh),
    //             label: const Text('Retry'),
    //           ),
    //       ],
    //     );
    //   } else {
    //     serverSelectionOrLogin = buildSelectServer();
    //   }
    // } else {
    //   serverSelectionOrLogin = buildLogin();
    // }
    // #pizcloud

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
                  SizedBox(height: constraints.maxHeight / 5),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        child: RotationTransition(
                          turns: logoAnimationController,
                          child: const PizCloudLogo(heroTag: 'logo'),
                        ),
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
