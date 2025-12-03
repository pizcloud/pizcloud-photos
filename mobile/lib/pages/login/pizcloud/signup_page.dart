import 'dart:convert';
import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/widgets/forms/login/email_input.dart';
import 'package:immich_mobile/widgets/forms/login/password_input.dart';
import 'package:immich_mobile/widgets/forms/login/loading_icon.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:openapi/api.dart';
import 'package:immich_mobile/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final String pizCloudServerUrl = AppConfig.pizCloudServerUrl.trim();

@RoutePage()
class SignupPage extends HookConsumerWidget {
  const SignupPage({super.key});

  Future<void> _postLoginFlow(BuildContext context, WidgetRef ref) async {
    final isBeta = Store.isBetaTimelineEnabled;
    if (isBeta) {
      await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();

      final bg = ref.read(backgroundSyncProvider);
      await bg.syncLocal(full: true);
      await bg.syncRemote();
      await bg.hashAssets();
      if (Store.get(StoreKey.syncAlbums, false)) {
        await bg.syncLinkedAlbum();
      }

      ref.read(websocketProvider.notifier).connect();
      // Redirect to main app
      context.replaceRoute(const TabShellRoute());
      return;
    }
    context.replaceRoute(const TabControllerRoute());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final isSubmitting = useState<bool>(false);

    final emailCtl = useTextEditingController();
    final passCtl = useTextEditingController();
    final confirmCtl = useTextEditingController();

    final emailFocus = useFocusNode();
    final passFocus = useFocusNode();
    final confirmFocus = useFocusNode();

    String? confirmValidator(String? value) {
      if (value == null || value.isEmpty) {
        return "please_reenter_your_password".tr();
      }
      if (value != passCtl.text) {
        return "the_reentered_password_does_not_match".tr();
      }
      return null;
    }

    Future<void> submit() async {
      if (!(formKey.currentState?.validate() ?? false)) return;

      final email = emailCtl.text.trim();
      final password = passCtl.text;

      isSubmitting.value = true;
      try {
        // Register
        await ref.read(authProvider.notifier).register(email, password);

        // Verify email
        final locale = context.locale;
        final lang = [
          locale.languageCode,
          if (locale.countryCode != null && locale.countryCode!.isNotEmpty) locale.countryCode,
        ].join('-');

        final base = pizCloudServerUrl.replaceAll(RegExp(r'/+$'), '');
        final uri = Uri.parse('$base/papi/auth/verify-email');

        http.Response response;
        try {
          response = await http.post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(<String, String>{'email': email, 'lang': lang}),
          );
        } catch (e) {
          ImmichToast.show(
            context: context,
            msg: "registration_success_but_verification_email_failed".tr(),
            toastType: ToastType.error,
          );
          return;
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          ImmichToast.show(
            context: context,
            msg: "verification_email_sent_check_inbox".tr(),
            toastType: ToastType.success,
          );
        } else {
          if (kDebugMode) {
            debugPrint(
              'Failed to send verification email: '
              'status=${response.statusCode} body=${response.body}',
            );
          }

          ImmichToast.show(
            context: context,
            msg: "registration_success_but_verification_email_failed".tr(),
            toastType: ToastType.error,
          );
        }
      } on ApiException catch (e) {
        String msg = "registration_failed".tr();
        if (e.code == 409) {
          msg = "email_already_exists".tr();
        } else if (e.code == 403) {
          msg = "server_does_not_allow_self_registration".tr();
        } else if (e.code == 400) {
          msg = e.message ?? "invalid_request".tr();
        } else if ((e.message ?? '').isNotEmpty) {
          msg = e.message!;
        }
        ImmichToast.show(context: context, msg: msg, toastType: ToastType.error);
      } catch (e) {
        ImmichToast.show(context: context, msg: e.toString(), toastType: ToastType.error);
      } finally {
        isSubmitting.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("sign_up").tr(),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.maybePop()),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              constraints: const BoxConstraints(maxWidth: 360),
              child: Form(
                key: formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Email
                      EmailInput(controller: emailCtl, focusNode: emailFocus, onSubmit: passFocus.requestFocus),
                      const SizedBox(height: 12),

                      // Password
                      PasswordInput(controller: passCtl, focusNode: passFocus, onSubmit: confirmFocus.requestFocus),
                      const SizedBox(height: 12),

                      // Confirm Password
                      TextFormField(
                        controller: confirmCtl,
                        focusNode: confirmFocus,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          labelText: 'reenter_password'.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        validator: confirmValidator,
                      ),

                      const SizedBox(height: 20),
                      isSubmitting.value
                          ? const LoadingIcon()
                          : ElevatedButton.icon(
                              onPressed: submit,
                              icon: const Icon(Icons.person_add_alt_1),
                              label: const Text("create_account", style: TextStyle(fontWeight: FontWeight.bold)).tr(),
                            ),

                      const SizedBox(height: 12),
                      TextButton.icon(
                        icon: const Icon(Icons.login),
                        onPressed: () => context.maybePop(),
                        label: const Text("already_have_an_account").tr(),
                      ),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
