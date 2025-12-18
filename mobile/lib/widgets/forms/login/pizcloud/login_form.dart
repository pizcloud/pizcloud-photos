import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/config/app_config.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/repositories/local_files_manager.repository.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/url_helper.dart';
// import 'package:immich_mobile/utils/version_compatibility.dart';
import 'package:immich_mobile/widgets/common/immich_title_text.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/common/pizcloud/pizcloud_logo.dart';
import 'package:immich_mobile/widgets/forms/login/loading_icon.dart';
import 'package:immich_mobile/widgets/forms/login/server_endpoint_input.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
// import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

import 'package:immich_mobile/services/pizcloud/google.service.dart';
import 'package:immich_mobile/services/pizcloud/login_with_email_service.dart';

final String pizCloudServerUrl = AppConfig.pizCloudServerUrl.trim(); // pizcloud

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
    final emailController = useTextEditingController.fromValue(TextEditingValue.empty);
    // final passwordController = useTextEditingController.fromValue(TextEditingValue.empty);
    final serverEndpointController = useTextEditingController.fromValue(TextEditingValue.empty);
    // final emailFocusNode = useFocusNode();
    // final passwordFocusNode = useFocusNode();
    final serverEndpointFocusNode = useFocusNode();
    final isLoading = useState<bool>(false);
    final isLoadingServer = useState<bool>(false);
    final isOauthEnable = useState<bool>(false);
    final isPasswordLoginEnable = useState<bool>(false);
    final oAuthButtonLabel = useState<String>('OAuth');
    final logoAnimationController = useAnimationController(duration: const Duration(seconds: 60))..repeat();
    // final serverInfo = ref.watch(serverInfoProvider);
    final warningMessage = useState<String?>(null);
    final loginFormKey = GlobalKey<FormState>();
    final ValueNotifier<String?> serverEndpoint = useState<String?>(null);

    final needsVerification = useState<bool>(false); // pizcloud: new email verification state

    final GoogleService googleService = GoogleService();
    final LoginWithEmailService loginWithEmailService = LoginWithEmailService();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    /// Fetch the server login credential and enables oAuth login if necessary
    /// Returns true if successful, false otherwise
    Future<void> getServerAuthSettings() async {
      final sanitizeServerUrl = sanitizeUrl(serverEndpointController.text);
      final serverUrl = punycodeEncodeUrl(sanitizeServerUrl);

      // Guard empty URL
      if (serverUrl.isEmpty) {
        ImmichToast.show(context: context, msg: "login_form_server_empty".tr(), toastType: ToastType.error);
      }

      try {
        isLoadingServer.value = true;

        warningMessage.value = null; // pizcloud

        final endpoint = await ref.read(authProvider.notifier).validateServerUrl(serverUrl);

        // Fetch and load server config and features
        await ref.read(serverInfoProvider.notifier).getServerInfo();

        final serverInfo = ref.read(serverInfoProvider);
        final features = serverInfo.serverFeatures;
        final config = serverInfo.serverConfig;

        isOauthEnable.value = features.oauthEnabled;
        isPasswordLoginEnable.value = features.passwordLogin;
        oAuthButtonLabel.value = config.oauthButtonText.isNotEmpty ? config.oauthButtonText : 'OAuth';

        serverEndpoint.value = endpoint;
      } on ApiException catch (e) {
        lastBootstrapFailed.value = true; // pizcloud

        ImmichToast.show(
          context: context,
          msg: e.message ?? 'login_form_api_exception'.tr(),
          toastType: ToastType.error,
          gravity: ToastGravity.TOP,
        );
        isOauthEnable.value = false;
        isPasswordLoginEnable.value = true;
        isLoadingServer.value = false;
      } on HandshakeException {
        ImmichToast.show(
          context: context,
          msg: 'login_form_handshake_exception'.tr(),
          toastType: ToastType.error,
          gravity: ToastGravity.TOP,
        );
        isOauthEnable.value = false;
        isPasswordLoginEnable.value = true;
        isLoadingServer.value = false;
      } catch (e) {
        ImmichToast.show(
          context: context,
          msg: 'login_form_server_error'.tr(),
          toastType: ToastType.error,
          gravity: ToastGravity.TOP,
        );
        isOauthEnable.value = false;
        isPasswordLoginEnable.value = true;
        isLoadingServer.value = false;
      }

      isLoadingServer.value = false;
    }

    // pizcloud

    String ensureApiSuffix(String url) {
      final u = url.trim().replaceAll(RegExp(r'/+$'), '');
      if (u.endsWith('/api')) return u;
      return '$u/api';
    }

    Future<bool> tryValidateUrl(String candidate) async {
      serverEndpointController.text = candidate;
      try {
        await getServerAuthSettings();
        return serverEndpoint.value != null;
      } catch (_) {
        return false;
      }
    }

    Future<void> bootstrapWithUrl(String start) async {
      isBootstrapping.value = true;
      lastBootstrapFailed.value = false;

      final candidates = <String>[start, ensureApiSuffix(start)];
      final backoffs = <int>[0, 800, 1500, 2500];

      bool done = false;
      for (final delayMs in backoffs) {
        if (delayMs > 0) await Future.delayed(Duration(milliseconds: delayMs));
        for (final c in candidates) {
          if (await tryValidateUrl(c)) {
            done = true;
            break;
          }
        }
        if (done) break;
      }

      if (!done) lastBootstrapFailed.value = true;
      isBootstrapping.value = false;
    }

    useEffect(() {
      final stored = getServerUrl();
      final fallback = AppConfig.defaultServer.trim();
      final start = (stored != null && stored.isNotEmpty) ? stored : (fallback.isNotEmpty ? fallback : null);
      if (start != null) {
        Future.microtask(() async {
          await bootstrapWithUrl(start);
        });
      }
      return null;
    }, []);
    // #pizcloud

    Future<void> handleSyncFlow() async {
      final backgroundManager = ref.read(backgroundSyncProvider);

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

    // pizcloud: new email verification flow
    // Future<bool> ensureEmailVerified(String email) async {
    //   final base = pizCloudServerUrl.replaceAll(RegExp(r'/+$'), '');
    //   if (base.isEmpty) {
    //     return true;
    //   }

    //   try {
    //     final uri = Uri.parse('$base/papi/auth/email-verification-status').replace(queryParameters: {'email': email});

    //     final resp = await http.get(uri, headers: const {'Accept': 'application/json'});

    //     if (resp.statusCode >= 200 && resp.statusCode < 300) {
    //       final data = jsonDecode(resp.body) as Map<String, dynamic>;
    //       final verified = data['verified'] == true;
    //       if (!verified) {
    //         needsVerification.value = true;
    //         ImmichToast.show(
    //           context: context,
    //           msg: "errors.email_not_verified".tr(),
    //           toastType: ToastType.error,
    //           gravity: ToastGravity.TOP,
    //         );
    //         return false;
    //       }
    //       needsVerification.value = false;
    //       return true;
    //     } else {
    //       needsVerification.value = false;
    //       ImmichToast.show(
    //         context: context,
    //         msg: "errors.login_email_verification_failed".tr(),
    //         toastType: ToastType.error,
    //         gravity: ToastGravity.TOP,
    //       );
    //       return false;
    //     }
    //   } catch (e) {
    //     needsVerification.value = false;
    //     ImmichToast.show(
    //       context: context,
    //       msg: "errors.login_email_verification_failed".tr(),
    //       toastType: ToastType.error,
    //       gravity: ToastGravity.TOP,
    //     );
    //     return false;
    //   }
    // }

    // Future<void> resendVerificationEmail() async {
    //   final email = emailController.text.trim();
    //   if (email.isEmpty) {
    //     ImmichToast.show(
    //       context: context,
    //       msg: "errors.email_required_for_resend".tr(),
    //       toastType: ToastType.error,
    //       gravity: ToastGravity.TOP,
    //     );
    //     return;
    //   }

    //   final base = pizCloudServerUrl.replaceAll(RegExp(r'/+$'), '');
    //   if (base.isEmpty) {
    //     ImmichToast.show(
    //       context: context,
    //       msg: "errors.resend_verification_email_failed".tr(),
    //       toastType: ToastType.error,
    //       gravity: ToastGravity.TOP,
    //     );
    //     return;
    //   }

    //   try {
    //     final locale = context.locale;
    //     final lang = [
    //       locale.languageCode,
    //       if (locale.countryCode != null && locale.countryCode!.isNotEmpty) locale.countryCode,
    //     ].join('-');

    //     final uri = Uri.parse('$base/papi/auth/verify-email');
    //     final resp = await http.post(
    //       uri,
    //       headers: const {'Content-Type': 'application/json'},
    //       body: jsonEncode(<String, String>{'email': email, 'lang': lang}),
    //     );

    //     if (resp.statusCode >= 200 && resp.statusCode < 300) {
    //       ImmichToast.show(
    //         context: context,
    //         msg: "verification_email_resent".tr(),
    //         toastType: ToastType.success,
    //         gravity: ToastGravity.TOP,
    //       );
    //       needsVerification.value = false;
    //     } else {
    //       ImmichToast.show(
    //         context: context,
    //         msg: "errors.resend_verification_email_failed".tr(),
    //         toastType: ToastType.error,
    //         gravity: ToastGravity.TOP,
    //       );
    //     }
    //   } catch (e) {
    //     ImmichToast.show(
    //       context: context,
    //       msg: "errors.resend_verification_email_failed".tr(),
    //       toastType: ToastType.error,
    //       gravity: ToastGravity.TOP,
    //     );
    //   }
    // }
    // #pizcloud

    String? validateEmail(String? value) {
      final email = value?.trim() ?? '';
      if (email.isEmpty) return 'Please enter your email';
      if (!email.contains('@') || email.startsWith('@')) {
        return 'Enter a valid email address';
      }
      return null;
    }

    // =================NEW======================
    Future<void> onGoogleLogin() async {
      // setState(() {
      //   _loading = true;
      //   _status = 'Signing in...';
      //   _error = null;
      //   _photosBody = '';
      // });

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
          unawaited(handleSyncFlow());
          ref.read(websocketProvider.notifier).connect();
          unawaited(context.replaceRoute(const TabShellRoute()));
          return;
        }
        if (permission.isGranted || permission.isLimited) {
          unawaited(ref.watch(backupProvider.notifier).resumeBackup());
        }
        unawaited(context.replaceRoute(const TabControllerRoute()));
        // setState(() {
        //   _status = 'Success';
        //   _photosBody = _stringify(result.photosResponse.data);
        // });
      } catch (e) {
        debugPrint('Google login FAILED: $e');
        // setState(() {
        //   _status = 'Error';
        //   _error = e.toString();
        //   // print(_error);
        // });
      } finally {
        // setState(() => _loading = false);
      }
    }

    Future<void> continueWithEmail() async {
      // if (!(formKey.currentState?.validate() ?? false)) return;

      final email = _emailController.text.trim();
      FocusScope.of(context).unfocus();
      try {
        final result = await loginWithEmailService.authenticate(email, ref);
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
          unawaited(handleSyncFlow());
          ref.read(websocketProvider.notifier).connect();
          unawaited(context.replaceRoute(const TabShellRoute()));
          return;
        }
        if (permission.isGranted || permission.isLimited) {
          unawaited(ref.watch(backupProvider.notifier).resumeBackup());
        }
        unawaited(context.replaceRoute(const TabControllerRoute()));
        // setState(() {
        //   _lastCallback = result.callbackUri;
        //   _status = result.photosResponse.statusCode != null ? 'HTTP ${result.photosResponse.statusCode}' : 'Done';
        //   _photosBody = _stringify(result.photosResponse.data);
        //   _error = null;
        // });
        // if (mounted) {
        //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logged in: $_status')));
        // }
      } on PlatformException catch (e) {
        // if (e.code == 'CANCELED') {
        //   setState(() {
        //     _status = 'Canceled';
        //     _error = null;
        //   });
        //   return;
        // }
        // setState(() {
        //   _status = 'Error';
        //   _error = e.toString();
        // });
        // if (mounted) {
        //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $e')));
        // }
      } catch (e) {
        // setState(() {
        //   _status = 'Error';
        //   _error = e.toString();
        // });
        // if (mounted) {
        //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $e')));
        // }
      } finally {
        // if (mounted) {
        //   setState(() {
        //     _launching = false;
        //     _handlingCallback = false;
        //   });
        // }
      }
    }

    // =======================================
    buildSelectServer() {
      const buttonRadius = 25.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ServerEndpointInput(
            controller: serverEndpointController,
            focusNode: serverEndpointFocusNode,
            onSubmit: getServerAuthSettings,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(buttonRadius),
                        bottomLeft: Radius.circular(buttonRadius),
                      ),
                    ),
                  ),
                  onPressed: () => context.pushRoute(const SettingsRoute()),
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text(""),
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(buttonRadius),
                        bottomRight: Radius.circular(buttonRadius),
                      ),
                    ),
                  ),
                  onPressed: isLoadingServer.value ? null : getServerAuthSettings,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('next', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)).tr(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (isLoadingServer.value) const LoadingIcon(),
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
                        children: [
                          const Text(
                            "Log in or sign up",
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ).tr(),
                        ],
                      ),
                      const SizedBox(height: 18),

                      ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Continue with Google'),
                        onPressed: () => onGoogleLogin(),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Divider(color: context.isDarkTheme ? Colors.white : Colors.black),
                      ),

                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: 'Email', hintText: 'you@example.com'),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.done,
                        validator: validateEmail,
                        onFieldSubmitted: (_) => continueWithEmail(),
                        // enabled: !busy,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: continueWithEmail,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Continue'),
                      ),
                      const SizedBox(height: 16),

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
            if (!isOauthEnable.value && !isPasswordLoginEnable.value) Center(child: const Text('login_disabled').tr()),
            const SizedBox(height: 12),
            if (!AppConfig.lockServer)
              TextButton.icon(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => serverEndpoint.value = null,
                label: const Text('back').tr(),
              ),
          ],
        ),
      );
    }

    // pizcloud
    // final serverSelectionOrLogin = serverEndpoint.value == null ? buildSelectServer() : buildLogin();

    final bool hasDefault = AppConfig.defaultServer.trim().isNotEmpty;
    Widget serverSelectionOrLogin;

    if (serverEndpoint.value == null) {
      final isAutoMode = (getServerUrl() != null && getServerUrl()!.isNotEmpty) || (hasDefault && AppConfig.lockServer);

      if (isAutoMode) {
        serverSelectionOrLogin = Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isBootstrapping.value) const LoadingIcon(),
            if (!isBootstrapping.value && lastBootstrapFailed.value)
              ElevatedButton.icon(
                onPressed: isLoadingServer.value
                    ? null
                    : () async {
                        final stored = getServerUrl();
                        final fallback = AppConfig.defaultServer.trim();
                        final start = (stored != null && stored.isNotEmpty)
                            ? stored
                            : (fallback.isNotEmpty ? fallback : null);
                        if (start != null) {
                          await bootstrapWithUrl(start);
                        }
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
          ],
        );
      } else {
        serverSelectionOrLogin = buildSelectServer();
      }
    } else {
      serverSelectionOrLogin = buildLogin();
    }
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

                  Form(key: loginFormKey, child: serverSelectionOrLogin),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
