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
// import 'package:immich_mobile/providers/gallery_permission.provider.dart';
// import 'package:immich_mobile/providers/background_sync.provider.dart';
// import 'package:immich_mobile/providers/websocket.provider.dart';
// import 'package:immich_mobile/routing/router.dart';
// import 'package:immich_mobile/domain/models/store.model.dart';
// import 'package:immich_mobile/entities/store.entity.dart';
import 'package:openapi/api.dart';
import 'package:immich_mobile/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final String pizCloudServerUrl = AppConfig.pizCloudServerUrl.trim();

@RoutePage()
class SignupPage extends HookConsumerWidget {
  const SignupPage({super.key});

  // Future<void> _postLoginFlow(BuildContext context, WidgetRef ref) async {
  //   final isBeta = Store.isBetaTimelineEnabled;
  //   if (isBeta) {
  //     await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();

  //     final bg = ref.read(backgroundSyncProvider);
  //     await bg.syncLocal(full: true);
  //     await bg.syncRemote();
  //     await bg.hashAssets();
  //     if (Store.get(StoreKey.syncAlbums, false)) {
  //       await bg.syncLinkedAlbum();
  //     }

  //     ref.read(websocketProvider.notifier).connect();
  //     // Redirect to main app
  //     context.replaceRoute(const TabShellRoute());
  //     return;
  //   }
  //   context.replaceRoute(const TabControllerRoute());
  // }

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

    // referral code controller + states
    final referralCtl = useTextEditingController();
    final referralLoading = useState<bool>(false);
    final referralError = useState<String?>(null);
    final referralInfo = useState<String?>(null);

    String? confirmValidator(String? value) {
      if (value == null || value.isEmpty) {
        return "please_reenter_your_password".tr();
      }
      if (value != passCtl.text) {
        return "the_reentered_password_does_not_match".tr();
      }
      return null;
    }

    String formatDisplayDate(DateTime date) {
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();
      return '$day/$month/$year';
    }

    Future<void> handleValidateReferral() async {
      referralError.value = null;
      referralInfo.value = null;

      final code = referralCtl.text.trim();
      if (code.isEmpty) {
        referralError.value = "register_referral.empty_error".tr();
        return;
      }

      referralLoading.value = true;
      try {
        final base = pizCloudServerUrl.replaceAll(RegExp(r'/+$'), '');
        final uri = Uri.parse('$base/papi/referral/validate');

        final email = emailCtl.text.trim();
        final body = <String, dynamic>{'code': code};
        if (email.isNotEmpty) {
          body['email'] = email;
        }

        final res = await http.post(uri, headers: const {'Content-Type': 'application/json'}, body: jsonEncode(body));

        if (res.statusCode < 200 || res.statusCode >= 300) {
          if (kDebugMode) {
            debugPrint('Failed to validate referral: status=${res.statusCode} body=${res.body}');
          }
          referralError.value = "register_referral.code_invalid".tr();
          return;
        }

        final data = jsonDecode(res.body);
        if (data is! Map<String, dynamic>) {
          referralError.value = "register_referral.code_invalid".tr();
          return;
        }

        final bool valid = data['valid'] == true;
        if (!valid) {
          final reason = (data['reason'] ?? '').toString().toUpperCase();
          if (reason == 'NOT_FOUND') {
            referralError.value = "register_referral.code_not_found".tr();
          } else if (reason == 'OWN_CODE') {
            referralError.value = "register_referral.code_own_code".tr();
          } else {
            referralError.value = "register_referral.code_invalid".tr();
          }
          return;
        }

        final discount = (data['discountPercent'] as num?)?.toInt() ?? 30;
        DateTime expiry;
        final validUntil = data['validUntil']?.toString();
        if (validUntil != null && validUntil.isNotEmpty) {
          try {
            expiry = DateTime.parse(validUntil);
          } catch (_) {
            final now = DateTime.now();
            expiry = DateTime(now.year + 1, now.month, now.day);
          }
        } else {
          final now = DateTime.now();
          expiry = DateTime(now.year + 1, now.month, now.day);
        }

        final formattedDate = formatDisplayDate(expiry);

        referralInfo.value = "register_referral.applied_message".tr(
          namedArgs: {'discount': discount.toString(), 'date': formattedDate},
        );
        referralError.value = null;
      } catch (e, s) {
        if (kDebugMode) {
          debugPrint('Error validating referral: $e\n$s');
        }
        referralError.value ??= "register_referral.code_invalid".tr();
      } finally {
        referralLoading.value = false;
      }
    }

    Future<void> syncReferralOnRegister(String base, String email, String referralCode) async {
      try {
        final uri = Uri.parse('$base/papi/referral/on-register');

        final code = referralCode.trim();
        final body = <String, dynamic>{'email': email};
        if (code.isNotEmpty) {
          body['referralCode'] = code;
        }

        final res = await http.post(uri, headers: const {'Content-Type': 'application/json'}, body: jsonEncode(body));

        if (res.statusCode < 200 || res.statusCode >= 300) {
          if (kDebugMode) {
            debugPrint(
              'Failed to sync referral on register: '
              'status=${res.statusCode} body=${res.body}',
            );
          }
        }
      } catch (e, s) {
        if (kDebugMode) {
          debugPrint('Error calling referral on-register: $e\n$s');
        }
      }
    }

    Future<void> submit() async {
      if (!(formKey.currentState?.validate() ?? false)) return;

      final email = emailCtl.text.trim();
      final password = passCtl.text;

      isSubmitting.value = true;
      try {
        // Register
        await ref.read(authProvider.notifier).register(email, password);

        final base = pizCloudServerUrl.replaceAll(RegExp(r'/+$'), '');

        await syncReferralOnRegister(base, email, referralCtl.text);

        // Verify email
        final locale = context.locale;
        final lang = [
          locale.languageCode,
          if (locale.countryCode != null && locale.countryCode!.isNotEmpty) locale.countryCode,
        ].join('-');

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

                      const SizedBox(height: 12),
                      _ReferralCodeField(
                        controller: referralCtl,
                        loading: referralLoading.value,
                        errorText: referralError.value,
                        infoText: referralInfo.value,
                        onApply: handleValidateReferral,
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

class _ReferralCodeField extends StatelessWidget {
  const _ReferralCodeField({
    required this.controller,
    required this.loading,
    required this.errorText,
    required this.infoText,
    required this.onApply,
  });

  final TextEditingController controller;
  final bool loading;
  final String? errorText;
  final String? infoText;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text("register_referral.label".tr(), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: "register_referral.placeholder".tr(),
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              child: ElevatedButton(
                onPressed: loading ? null : onApply,
                style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
                child: loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text("register_referral.apply".tr()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          "register_referral.description".tr(),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 4),
        if (loading)
          Text(
            "register_referral.validating".tr(),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7)),
          )
        else if (errorText != null && errorText!.isNotEmpty)
          Text(errorText!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.red))
        else if (infoText != null && infoText!.isNotEmpty)
          Text(infoText!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.green)),
      ],
    );
  }
}
