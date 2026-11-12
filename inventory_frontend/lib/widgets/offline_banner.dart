import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:inventory_frontend/services/sale_outbox.dart';
import 'package:inventory_frontend/utils/connection_status.dart';

/// Shows when the app is offline and how many sales are still waiting to reach the server.
/// Renders nothing when online with nothing to sync.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  static String _age(DateTime from, AppLocalizations l10n) {
    final age = DateTime.now().difference(from);
    if (age.inMinutes < 1) return l10n.ageJustNow;
    if (age.inHours < 1) return l10n.ageMinutes(age.inMinutes);
    if (age.inDays < 1) return l10n.ageHours(age.inHours);
    return l10n.ageDays(age.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final connection = ConnectionStatus.instance;
    final outbox = SaleOutbox.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([connection, outbox]),
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final scheme = Theme.of(context).colorScheme;
        final pending = outbox.pending.length;
        final failed = outbox.failed.length;
        final offline = connection.isOffline;
        if (!offline && pending == 0 && failed == 0) return const SizedBox.shrink();

        final Color background;
        final Color foreground;
        final IconData icon;
        final String message;
        if (failed > 0) {
          background = scheme.errorContainer;
          foreground = scheme.onErrorContainer;
          icon = Icons.error_outline;
          message = l10n.salesFailedToSync(failed);
        } else if (offline) {
          background = Colors.orange.shade100;
          foreground = Colors.orange.shade900;
          icon = Icons.cloud_off_rounded;
          // Say how old the saved data is: stock shown offline can be out of date
          final from = connection.savedDataFrom;
          final saved = from == null ? l10n.offlineSavedData : l10n.offlineSavedDataFrom(_age(from, l10n));
          message = pending > 0 ? '$saved · ${l10n.salesWaitingToSync(pending)}' : saved;
        } else {
          background = scheme.secondaryContainer;
          foreground = scheme.onSecondaryContainer;
          icon = Icons.cloud_upload_outlined;
          message = l10n.salesWaitingToSync(pending);
        }

        return Material(
          color: background,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: 12),
                  Expanded(child: Text(message, style: TextStyle(color: foreground, fontSize: 13))),
                  if (pending > 0)
                    outbox.isSyncing
                        ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                          ),
                        )
                        : TextButton(
                          onPressed: outbox.sync,
                          style: TextButton.styleFrom(foregroundColor: foreground),
                          child: Text(l10n.syncNow),
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
