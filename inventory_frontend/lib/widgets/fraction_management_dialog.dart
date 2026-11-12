import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/models/item.dart';
import 'package:inventory_frontend/providers/item_provider.dart';
import 'package:inventory_frontend/widgets/auth_layout.dart';

/// Adds a unit (fraction) to an item, listing the units it already has. Closes once the unit
/// is saved.
class FractionManagementDialog extends StatefulWidget {
  final Item item;

  const FractionManagementDialog({super.key, required this.item});

  @override
  State<FractionManagementDialog> createState() => _FractionManagementDialogState();
}

class _FractionManagementDialogState extends State<FractionManagementDialog> {
  static final _money = NumberFormat('#,##0.00');
  static final _num = NumberFormat('#,##0.##');
  static final _decimal = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ratioController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ratioController.dispose();
    _sellingPriceController.dispose();
    _purchasePriceController.dispose();
    super.dispose();
  }

  Future<void> _addFraction() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context)!;
    final itemProvider = context.read<ItemProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    setState(() => _isSubmitting = true);
    final success = await itemProvider.createFraction(
      widget.item.id,
      _nameController.text.trim(),
      double.parse(_ratioController.text),
      double.parse(_sellingPriceController.text),
      double.parse(_purchasePriceController.text),
      isUnit: false,
    );

    if (success) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.fractionAddedSuccessfully)));
      navigator.pop(); // Close the dialog after a successful addition
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(itemProvider.error ?? l10n.error), backgroundColor: errorColor));
    if (mounted) setState(() => _isSubmitting = false);
  }

  String? _validRatio(String? v, AppLocalizations l10n) {
    if (v == null || v.trim().isEmpty) return l10n.pleaseEnterRatio;
    final n = double.tryParse(v);
    if (n == null) return l10n.pleaseEnterValidNumber;
    if (n <= 0) return l10n.catalogRatioMustBePositive;
    return null;
  }

  String? _validPrice(String? v, AppLocalizations l10n) {
    if (v == null || v.trim().isEmpty) return l10n.pleaseEnterPrice;
    final n = double.tryParse(v);
    if (n == null) return l10n.pleaseEnterValidNumber;
    if (n < 0) return l10n.catalogPriceNotNegative;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Follow the provider so the list of existing units stays current
    final existing = context.select<ItemProvider, List<Fraction>>((p) {
      for (final i in p.items) {
        if (i.id == widget.item.id) return i.fractions ?? const [];
      }
      return widget.item.fractions ?? const [];
    });

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.manageUnitsFor(widget.item.name),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (existing.isNotEmpty) ...[
                        AuthSectionLabel(text: l10n.existingUnits, icon: Icons.straighten_rounded),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              for (final f in existing)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          f.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Text(
                                        '×${_num.format(f.ratio)}',
                                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '${l10n.currencySymbol} ${_money.format(f.sellingPrice)}',
                                        style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      AuthSectionLabel(text: l10n.addUnit, icon: Icons.add_rounded),
                      const SizedBox(height: 6),
                      Text(
                        l10n.addPrimarySellingUnitDescription,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameController,
                        enabled: !_isSubmitting,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: authInputDecoration(
                          context,
                          label: l10n.unitName,
                          icon: Icons.label_outline_rounded,
                        ).copyWith(hintText: l10n.catalogUnitNameHint),
                        validator: (v) => (v == null || v.trim().isEmpty) ? l10n.pleaseEnterName : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ratioController,
                        enabled: !_isSubmitting,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_decimal],
                        decoration: authInputDecoration(
                          context,
                          label: l10n.ratio,
                          icon: Icons.functions_rounded,
                          helper: l10n.catalogRatioHelper,
                        ),
                        validator: (v) => _validRatio(v, l10n),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _sellingPriceController,
                              enabled: !_isSubmitting,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [_decimal],
                              decoration: authInputDecoration(context, label: l10n.soldPriceLabel),
                              validator: (v) => _validPrice(v, l10n),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _purchasePriceController,
                              enabled: !_isSubmitting,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [_decimal],
                              decoration: authInputDecoration(context, label: l10n.purchasePrice),
                              validator: (v) => _validPrice(v, l10n),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton(
                onPressed: _isSubmitting ? null : _addFraction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child:
                    _isSubmitting
                        ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary),
                        )
                        : Text(l10n.addUnit, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
