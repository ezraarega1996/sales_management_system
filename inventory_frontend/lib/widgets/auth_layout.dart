import 'package:flutter/material.dart';

import 'package:inventory_frontend/widgets/language_selector.dart';

/// Shared frame for the login and registration pages: a gradient header (same look as the
/// welcome page and dashboard) with the logo and a title, and the form in a card that
/// overlaps the header.
class AuthLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  /// Shown under the card, e.g. "No account? Register".
  final Widget? footer;

  const AuthLayout({super.key, required this.title, required this.subtitle, required this.child, this.footer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onHero = scheme.onPrimary;
    final topInset = MediaQuery.of(context).padding.top;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Stack(
          children: [
            // Header background; the card below overlaps its bottom edge
            Container(
              height: topInset + 250,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.55)!],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, topInset + 4, 16, MediaQuery.of(context).padding.bottom + 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (canPop)
                            IconButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: Icon(Icons.arrow_back_rounded, color: onHero),
                            ),
                          const Spacer(),
                          DefaultTextStyle.merge(
                            style: TextStyle(color: onHero, fontWeight: FontWeight.w600),
                            child: const LanguageSelector(),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(color: onHero, borderRadius: BorderRadius.circular(18)),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: Image.asset('assets/images/logo.jpg', width: 56, height: 56, fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      color: onHero,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: TextStyle(color: onHero.withValues(alpha: 0.88), fontSize: 14, height: 1.3),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Card(
                        elevation: 6,
                        shadowColor: Colors.black.withValues(alpha: 0.25),
                        margin: EdgeInsets.zero,
                        color: scheme.surfaceContainerLowest,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        child: Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 20), child: child),
                      ),
                      if (footer != null) ...[const SizedBox(height: 16), footer!],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded, filled input style used on the auth pages.
InputDecoration authInputDecoration(
  BuildContext context, {
  required String label,
  IconData? icon,
  Widget? suffix,
  String? helper,
}) {
  final scheme = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    labelText: label,
    helperText: helper,
    prefixIcon: icon != null ? Icon(icon) : null,
    suffixIcon: suffix,
    filled: true,
    fillColor: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border(Colors.transparent),
    enabledBorder: border(Colors.transparent),
    focusedBorder: border(scheme.primary, 2),
    errorBorder: border(scheme.error),
    focusedErrorBorder: border(scheme.error, 2),
  );
}

/// Small uppercase label that splits a form into groups.
class AuthSectionLabel extends StatelessWidget {
  final String text;
  final IconData icon;

  const AuthSectionLabel({super.key, required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          text.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

/// Full-width primary button with a spinner while [isLoading].
class AuthSubmitButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  const AuthSubmitButton({super.key, required this.label, required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child:
          isLoading
              ? SizedBox(
                height: 22,
                width: 22,
                // The button is disabled (greyed) while loading, so draw the spinner in the brand colour
                child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary),
              )
              : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}
