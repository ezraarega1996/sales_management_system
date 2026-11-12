import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/screens/admin/admin_dashboard.dart';
import 'package:inventory_frontend/screens/auth/business_registration_screen.dart';
import 'package:inventory_frontend/screens/owner/owner_dashboard.dart';
import 'package:inventory_frontend/screens/salesman/salesman_dashboard.dart';
import 'package:inventory_frontend/widgets/auth_layout.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.login(_usernameController.text.trim(), _passwordController.text);
    if (!mounted) return;

    if (success) {
      final Widget home =
          authProvider.isAdmin
              ? const AdminDashboard()
              : authProvider.isOwner
              ? const OwnerDashboard()
              : const SalesmanDashboard();
      // Clear the welcome page from the stack so Back doesn't return to it
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => home), (_) => false);
    } else {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authProvider.error ?? l10n.loginFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AuthLayout(
      title: l10n.loginWelcomeBack,
      subtitle: l10n.loginWelcomeSubtitle,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              l10n.loginNoAccount,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed:
                () => Navigator.of(
                  context,
                ).pushReplacement(MaterialPageRoute(builder: (_) => const BusinessRegistrationScreen())),
            child: Text(l10n.registerBusiness, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: authInputDecoration(context, label: l10n.usernameLabel, icon: Icons.person_outline_rounded),
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                autocorrect: false,
                validator: (value) => (value == null || value.trim().isEmpty) ? l10n.usernameRequired : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
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
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _login(),
                validator: (value) => (value == null || value.isEmpty) ? l10n.passwordRequired : null,
              ),
              const SizedBox(height: 24),
              AuthSubmitButton(label: l10n.loginButton, isLoading: authProvider.isLoading, onPressed: _login),
            ],
          ),
        ),
      ),
    );
  }
}
