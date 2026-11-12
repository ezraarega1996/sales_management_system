import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/screens/auth/login_screen.dart';
import 'package:inventory_frontend/widgets/auth_layout.dart';

class BusinessRegistrationScreen extends StatefulWidget {
  const BusinessRegistrationScreen({super.key});

  @override
  State<BusinessRegistrationScreen> createState() => _BusinessRegistrationScreenState();
}

class _BusinessRegistrationScreenState extends State<BusinessRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _ownerUsernameController = TextEditingController();
  final _ownerPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _ownerPhoneController.dispose();
    _ownerUsernameController.dispose();
    _ownerPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _registerBusiness() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    final success = await authProvider.registerBusiness({
      'name': _businessNameController.text.trim(),
      'ownerName': _ownerNameController.text.trim(),
      'ownerPhone': _ownerPhoneController.text.trim(),
      'ownerUsername': _ownerUsernameController.text.trim(),
      'ownerPassword': _ownerPasswordController.text,
    });

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.registerSuccess)));
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authProvider.error ?? l10n.registerFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    String? required(String? v, String message) => (v == null || v.trim().isEmpty) ? message : null;

    return AuthLayout(
      title: l10n.registerTitle,
      subtitle: l10n.registerSubtitle,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              l10n.registerHaveAccount,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed:
                () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen())),
            child: Text(l10n.loginButton, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthSectionLabel(text: l10n.registerSectionBusiness, icon: Icons.storefront_outlined),
            const SizedBox(height: 12),
            TextFormField(
              controller: _businessNameController,
              decoration: authInputDecoration(context, label: l10n.registerBusinessName, icon: Icons.business_outlined),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (v) => required(v, l10n.registerBusinessNameRequired),
            ),
            const SizedBox(height: 24),
            AuthSectionLabel(text: l10n.registerSectionOwner, icon: Icons.person_outline_rounded),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ownerNameController,
              decoration: authInputDecoration(context, label: l10n.registerOwnerName, icon: Icons.badge_outlined),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              validator: (v) => required(v, l10n.registerOwnerNameRequired),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ownerPhoneController,
              decoration: authInputDecoration(context, label: l10n.registerOwnerPhone, icon: Icons.phone_outlined),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              validator: (v) => required(v, l10n.registerOwnerPhoneRequired),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ownerUsernameController,
              decoration: authInputDecoration(
                context,
                label: l10n.usernameLabel,
                icon: Icons.alternate_email_rounded,
                helper: l10n.registerUsernameHelper,
              ),
              autocorrect: false,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newUsername],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l10n.usernameRequired;
                if (v.trim().length < 4) return l10n.registerUsernameTooShort;
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ownerPasswordController,
              obscureText: _obscurePassword,
              decoration: authInputDecoration(
                context,
                label: l10n.passwordLabel,
                icon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) {
                if (v == null || v.isEmpty) return l10n.passwordRequired;
                if (v.length < 6) return l10n.passwordMustBeAtLeast6Characters;
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              decoration: authInputDecoration(
                context,
                label: l10n.registerConfirmPassword,
                icon: Icons.lock_reset_rounded,
                suffix: IconButton(
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _registerBusiness(),
              validator: (v) {
                if (v == null || v.isEmpty) return l10n.pleaseConfirmPassword;
                if (v != _ownerPasswordController.text) return l10n.passwordsDoNotMatch;
                return null;
              },
            ),
            const SizedBox(height: 24),
            AuthSubmitButton(
              label: l10n.registerSubmit,
              isLoading: authProvider.isLoading,
              onPressed: _registerBusiness,
            ),
          ],
        ),
      ),
    );
  }
}
