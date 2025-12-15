import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:immich_mobile/services/pizcloud/referral_payout_method.service.dart';

@RoutePage()
class ReferralPayoutMethodPage extends HookConsumerWidget {
  const ReferralPayoutMethodPage({super.key, required this.userEmail, this.onSaved});

  final String userEmail;
  final VoidCallback? onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final payoutService = referralPayoutMethodService;

    final loading = useState<bool>(true);
    final saving = useState<bool>(false);
    final error = useState<String?>(null);

    final method = useState<String>('bank');

    final bankNameController = useTextEditingController();
    final bankAccountController = useTextEditingController();
    final bankHolderController = useTextEditingController();

    final paypalEmailController = useTextEditingController();
    final paypalFullNameController = useTextEditingController();

    Future<void> load() async {
      loading.value = true;
      error.value = null;

      try {
        final pm = await payoutService.loadPayoutMethod(userEmail);

        if (pm != null) {
          method.value = pm.method == 'paypal' ? 'paypal' : 'bank';
          bankNameController.text = pm.bankName ?? '';
          bankAccountController.text = pm.bankAccountNumber ?? '';
          bankHolderController.text = pm.bankAccountHolderName ?? '';
          paypalEmailController.text = pm.paypalEmail ?? '';
          paypalFullNameController.text = pm.paypalFullName ?? '';
        }
      } catch (e, s) {
        debugPrint('Error loading payout method: $e\n$s');
        error.value = 'referral.payout_method_load_error'.tr();
      } finally {
        loading.value = false;
      }
    }

    useEffect(() {
      load();
      return null;
    }, []);

    Future<void> save() async {
      error.value = null;

      final currentMethod = method.value;

      // Validate client-side
      if (currentMethod == 'bank') {
        if (bankNameController.text.trim().isEmpty ||
            bankAccountController.text.trim().isEmpty ||
            bankHolderController.text.trim().isEmpty) {
          error.value = 'referral.withdraw_bank_info_required'.tr();
          return;
        }
      } else {
        if (paypalEmailController.text.trim().isEmpty) {
          error.value = 'referral.withdraw_paypal_info_required'.tr();
          return;
        }
      }

      saving.value = true;

      try {
        final code = await payoutService.savePayoutMethod(
          email: userEmail,
          method: currentMethod,
          bankName: bankNameController.text,
          bankAccountNumber: bankAccountController.text,
          bankAccountHolderName: bankHolderController.text,
          paypalEmail: paypalEmailController.text,
          paypalFullName: paypalFullNameController.text,
        );

        if (code != null) {
          switch (code) {
            case 'BANK_INFO_REQUIRED':
              error.value = 'referral.withdraw_bank_info_required'.tr();
              break;
            case 'PAYPAL_INFO_REQUIRED':
              error.value = 'referral.withdraw_paypal_info_required'.tr();
              break;
            case 'INVALID_WITHDRAW_METHOD':
              error.value = 'referral.withdraw_method_invalid'.tr();
              break;
            case 'EMAIL_REQUIRED':
            case 'USER_NOT_FOUND':
              error.value = 'referral.apply_missing_email'.tr();
              break;
            default:
              error.value = 'referral.payout_method_save_error'.tr();
          }
          return;
        }

        // success
        onSaved?.call();

        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('referral.payout_method_save_success'.tr())));
          Navigator.of(context).pop();
        }
      } catch (e, s) {
        debugPrint('Error saving payout method: $e\n$s');
        error.value = 'referral.payout_method_save_error'.tr();
      } finally {
        saving.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text('referral.payout_method_title'.tr())),
      body: SafeArea(
        child: loading.value
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'referral.payout_method_description'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'referral.withdraw_method_label'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Text('referral.withdraw_method_bank'.tr()),
                            selected: method.value == 'bank',
                            onSelected: (v) {
                              if (!v) return;
                              method.value = 'bank';
                              error.value = null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: Text('referral.withdraw_method_paypal'.tr()),
                            selected: method.value == 'paypal',
                            onSelected: (v) {
                              if (!v) return;
                              method.value = 'paypal';
                              error.value = null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (method.value == 'bank') ...[
                      TextField(
                        controller: bankNameController,
                        decoration: InputDecoration(
                          labelText: 'referral.withdraw_bank_name_label'.tr(),
                          hintText: 'referral.withdraw_bank_name_hint'.tr(),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: bankAccountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'referral.withdraw_bank_account_label'.tr(),
                          hintText: 'referral.withdraw_bank_account_hint'.tr(),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: bankHolderController,
                        decoration: InputDecoration(
                          labelText: 'referral.withdraw_bank_account_holder_label'.tr(),
                          hintText: 'referral.withdraw_bank_account_holder_hint'.tr(),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: paypalEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'referral.withdraw_paypal_email_label'.tr(),
                          hintText: 'referral.withdraw_paypal_email_hint'.tr(),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: paypalFullNameController,
                        decoration: InputDecoration(
                          labelText: 'referral.withdraw_paypal_fullname_label'.tr(),
                          hintText: 'referral.withdraw_paypal_fullname_hint'.tr(),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),
                    ],
                    if (error.value != null && error.value!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(error.value!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.red.shade500)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: saving.value ? null : save,
                        child: saving.value
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text('referral.payout_method_save_button'.tr()),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
