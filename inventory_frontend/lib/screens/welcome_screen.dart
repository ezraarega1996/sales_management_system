import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:inventory_frontend/screens/auth/business_registration_screen.dart';
import 'package:inventory_frontend/screens/auth/login_screen.dart';
import 'package:inventory_frontend/widgets/language_selector.dart';

/// First screen for signed-out users: what the app does, then Sign in / Register.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onHero = scheme.onPrimary;

    final features = [
      (Icons.point_of_sale_rounded, l10n.welcomeFeatureSellTitle, l10n.welcomeFeatureSellBody),
      (Icons.inventory_2_rounded, l10n.welcomeFeatureStockTitle, l10n.welcomeFeatureStockBody),
      (Icons.insights_rounded, l10n.welcomeFeatureInsightsTitle, l10n.welcomeFeatureInsightsBody),
      (Icons.cloud_off_rounded, l10n.welcomeFeatureOfflineTitle, l10n.welcomeFeatureOfflineBody),
    ];

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero
            Container(
              padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 8, 24, 36),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.55)!],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    // The language button sits on the gradient, so draw its label light
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: onHero, fontWeight: FontWeight.w600),
                      child: const LanguageSelector(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: onHero,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset('assets/images/logo.jpg', width: 84, height: 84, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.appTitle,
                    style: TextStyle(
                      color: onHero.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.welcomeTitle,
                    style: TextStyle(color: onHero, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.welcomeSubtitle,
                    style: TextStyle(color: onHero.withValues(alpha: 0.9), fontSize: 15, height: 1.4),
                  ),
                ],
              ),
            ),

            // Why owners choose it
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.welcomeWhyTitle,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 12),
                    _Benefit(
                      icon: Icons.savings_outlined,
                      title: l10n.welcomeBenefitCostTitle,
                      body: l10n.welcomeBenefitCostBody,
                    ),
                    _Benefit(
                      icon: Icons.store_mall_directory_outlined,
                      title: l10n.welcomeBenefitShopsTitle,
                      body: l10n.welcomeBenefitShopsBody,
                    ),
                    _Benefit(
                      icon: Icons.handshake_outlined,
                      title: l10n.welcomeBenefitTrustTitle,
                      body: l10n.welcomeBenefitTrustBody,
                    ),
                  ],
                ),
              ),
            ),

            // Features
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Two columns on phones, one on very narrow screens
                  final columns = constraints.maxWidth >= 340 ? 2 : 1;
                  final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final (icon, title, body) in features)
                        SizedBox(width: width, child: _FeatureCard(icon: icon, title: title, body: body)),
                    ],
                  );
                },
              ),
            ),

            // Actions
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed:
                        () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.login_rounded),
                    label: Text(l10n.welcomeSignIn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed:
                        () => Navigator.of(
                          context,
                        ).push(MaterialPageRoute(builder: (_) => const BusinessRegistrationScreen())),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.add_business_outlined),
                    label: Text(
                      l10n.registerBusiness,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.welcomeSalesmanHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Benefit({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: scheme.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _FeatureCard({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 10),
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.35)),
        ],
      ),
    );
  }
}
