import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/widgets/auth_layout.dart';

/// Lets the signed-in user change their password. Pushed from the dashboards' drawers.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context)!;
    final authProvider = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isLoading = true);
    try {
      final success = await authProvider.changePassword(
        _currentPasswordController.text.trim(),
        _newPasswordController.text.trim(),
      );
      if (!mounted) return;

      if (success) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.peoplePasswordChanged)));
        navigator.pop();
      } else {
        messenger.showSnackBar(SnackBar(content: Text(authProvider.error ?? l10n.peoplePasswordChangeFailed)));
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _visibilityToggle(bool obscured, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AuthLayout(
      title: l10n.changePasswordMenu,
      subtitle: l10n.peopleChangePasswordSubtitle,
      footer: Center(
        child: TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).maybePop(),
          child: Text(l10n.cancel),
        ),
      ),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _currentPasswordController,
                enabled: !_isLoading,
                obscureText: _obscureCurrent,
                decoration: authInputDecoration(
                  context,
                  label: l10n.peopleCurrentPassword,
                  icon: Icons.lock_outline_rounded,
                  suffix: _visibilityToggle(_obscureCurrent, () => setState(() => _obscureCurrent = !_obscureCurrent)),
                ),
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.password],
                validator: (v) => (v == null || v.isEmpty) ? l10n.peopleCurrentPasswordRequired : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _newPasswordController,
                enabled: !_isLoading,
                obscureText: _obscureNew,
                decoration: authInputDecoration(
                  context,
                  label: l10n.newPassword,
                  icon: Icons.lock_reset_rounded,
                  helper: l10n.passwordMustBeAtLeast6Characters,
                  suffix: _visibilityToggle(_obscureNew, () => setState(() => _obscureNew = !_obscureNew)),
                ),
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) {
                  if (v == null || v.isEmpty) return l10n.pleaseEnterNewPassword;
                  if (v.trim().length < 6) return l10n.passwordMustBeAtLeast6Characters;
                  if (v.trim() == _currentPasswordController.text.trim()) return l10n.peopleNewPasswordSameAsCurrent;
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmPasswordController,
                enabled: !_isLoading,
                obscureText: _obscureConfirm,
                decoration: authInputDecoration(
                  context,
                  label: l10n.confirmNewPassword,
                  icon: Icons.lock_reset_rounded,
                  suffix: _visibilityToggle(_obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm)),
                ),
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) => _changePassword(),
                validator: (v) {
                  if (v == null || v.isEmpty) return l10n.pleaseConfirmPassword;
                  if (v != _newPasswordController.text) return l10n.passwordsDoNotMatch;
                  return null;
                },
              ),
              const SizedBox(height: 24),
              AuthSubmitButton(label: l10n.changePasswordMenu, isLoading: _isLoading, onPressed: _changePassword),
            ],
          ),
        ),
      ),
    );
  }
}
