import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/models/available_item.dart';
import 'package:inventory_frontend/providers/sales_provider.dart';
import 'package:inventory_frontend/providers/available_item_provider.dart';
import 'package:inventory_frontend/providers/item_provider.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/widgets/offline_banner.dart';
import 'package:inventory_frontend/widgets/custom_button.dart';
import 'package:inventory_frontend/widgets/custom_text_field.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SellItemScreen extends StatefulWidget {
  final AvailableItem? preSelectedAvailableItem;
  final Fraction? preSelectedAvailableFraction;

  const SellItemScreen({super.key, this.preSelectedAvailableItem, this.preSelectedAvailableFraction});

  @override
  State<SellItemScreen> createState() => _SellItemScreenState();
}

class _SellItemScreenState extends State<SellItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _purchasePriceController = TextEditingController();

  AvailableItem? _selectedAvailableItem;
  Fraction? _selectedFraction;
  double _expectedAmount = 0;
  double _profit = 0;
  double _availableQuantity = 0;
  bool _isLoading = true;
  String? _error;
  bool _isSubmitting = false;

  // Memoized providers
  late final AvailableItemProvider _availableItemProvider;
  late final SalesProvider _salesProvider;
  late final ItemProvider _itemProvider;

  @override
  void initState() {
    super.initState();
    _initializeProviders();
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _initializeProviders() {
    _availableItemProvider = Provider.of<AvailableItemProvider>(context, listen: false);
    _salesProvider = Provider.of<SalesProvider>(context, listen: false);
    _itemProvider = Provider.of<ItemProvider>(context, listen: false);
  }

  /// Loads stock. Reuses data fetched in the last minute (e.g. when coming from the Available
  /// Items list) unless [force] is set, and falls back to the saved copy when offline.
  Future<void> _loadData({bool force = false}) async {
    if (!mounted) return;
    final hasData = _availableItemProvider.availableItems.isNotEmpty;
    setState(() {
      _isLoading = !hasData;
      _error = null;
    });
    await _availableItemProvider.fetchAvailableItems(force: force);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      // Only a problem if there is nothing (not even saved data) to sell from
      if (_availableItemProvider.availableItems.isEmpty && _availableItemProvider.error != null) {
        _error = AppLocalizations.of(context)!.loadFailedNoData;
      }
    });
    _setupPreSelectedValues();
  }

  void _setupPreSelectedValues() {
    // Priority: preSelectedAvailableItem and preSelectedAvailableFraction
    if (widget.preSelectedAvailableItem != null) {
      final assignedItems = _getAssignedItems();
      try {
        final matching = assignedItems.firstWhere((item) => item.id == widget.preSelectedAvailableItem!.id);
        _selectedAvailableItem = matching;
      } catch (e) {
        // No match found, leave as null
      }
    }

    if (_selectedAvailableItem != null) {
      if (widget.preSelectedAvailableFraction != null) {
        final fractions = _selectedAvailableItem!.item?.fractions ?? [];
        try {
          final matchingFraction = fractions.firstWhere((f) => f.id == widget.preSelectedAvailableFraction!.id);
          _selectedFraction = matchingFraction;
          _updatePriceFields(matchingFraction);
          _updateExpectedAmount();
          _fetchAvailableQuantity();
        } catch (e) {
          // No match found, leave as null
        }
      }
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _sellingPriceController.dispose();
    _purchasePriceController.dispose();
    super.dispose();
  }

  Future<void> _fetchAvailableQuantity() async {
    if (_selectedAvailableItem == null || _selectedFraction == null) return;

    try {
      final availableQuantity = _selectedAvailableItem!.quantity / _selectedFraction!.ratio;
      if (!mounted) return;

      setState(() {
        _availableQuantity = double.parse(availableQuantity.toStringAsFixed(2));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to fetch available quantity. Please try again.';
        _availableQuantity = 0;
      });
    }
  }

  void _updateExpectedAmount() {
    if (_selectedFraction == null || _quantityController.text.isEmpty) {
      setState(() {
        _expectedAmount = 0;
        _profit = 0;
      });
      return;
    }

    final quantity = double.tryParse(_quantityController.text) ?? 0;
    final sellingPrice = double.tryParse(_sellingPriceController.text) ?? _selectedFraction!.sellingPrice;
    final purchasePrice = double.tryParse(_purchasePriceController.text) ?? _selectedFraction!.purchasePrice;

    setState(() {
      _expectedAmount = quantity * sellingPrice;
      _profit = (sellingPrice - purchasePrice) * quantity;
    });
  }

  Future<void> _sellItem() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAvailableItem == null || _selectedFraction == null) {
      _showErrorSnackBar(l10n.pleaseSelectItemAndFraction);
      return;
    }

    final quantity = double.parse(_quantityController.text);
    final sellingPrice = double.tryParse(_sellingPriceController.text);
    final purchasePrice = double.tryParse(_purchasePriceController.text);

    if (sellingPrice == null || purchasePrice == null) {
      _showErrorSnackBar(l10n.pleaseEnterValidNumber);
      return;
    }

    if (quantity > _availableQuantity) {
      _showErrorSnackBar(l10n.availableQuantityIs(_availableQuantity));
      return;
    }

    setState(() {
      _isSubmitting = true;
    });
    try {
      final availableItem = _selectedAvailableItem!;
      final fraction = _selectedFraction!;

      // Only owners may change catalogue prices (the endpoint is owner-only); a salesman's
      // edited price applies to this sale only. A failed price update never blocks the sale.
      String? priceError;
      if (context.read<AuthProvider>().isOwner) {
        priceError = await _maybeUpdateFractionPrices(sellingPrice, purchasePrice);
      }

      // Saved on the phone immediately and sent in the background, so this works offline.
      // Stock shown on screen is reduced right away; no need to re-download the stock list.
      final confirmed = await _salesProvider.createSale(
        {
          'itemId': availableItem.item!.id,
          'shopId': availableItem.shopId,
          'fractionId': fraction.id,
          'quantity': quantity,
          'amount': _expectedAmount,
          'profit': _profit,
        },
        availableItemId: availableItem.id,
        units: quantity * fraction.ratio,
        itemName: availableItem.item?.name ?? '',
        fractionName: fraction.name,
      );

      if (!mounted) return;
      _showSuccessSnackBar(
        priceError != null
            ? l10n.priceNotUpdated(priceError)
            : confirmed
            ? l10n.itemSoldSuccessfully
            : l10n.saleSavedOffline,
      );
      _resetForm();
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(l10n.failedToProcessSale);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _resetForm() {
    setState(() {
      _quantityController.clear();
      _expectedAmount = 0;
      _availableQuantity = 0;
      _selectedAvailableItem = null;
      _selectedFraction = null;
    });
    _updatePriceFields(null);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<AvailableItem> _getAssignedItems() {
    return _availableItemProvider.availableItems;
  }

  void _handleItemChange(AvailableItem? value) {
    setState(() {
      _selectedAvailableItem = value;
      _selectedFraction = null;
      _quantityController.clear();
      _expectedAmount = 0;
      _availableQuantity = 0;
    });
    _updatePriceFields(null);
  }

  void _updatePriceFields(Fraction? fraction) {
    if (fraction == null) {
      _sellingPriceController.clear();
      _purchasePriceController.clear();
      return;
    }
    _sellingPriceController.text = fraction.sellingPrice.toStringAsFixed(2);
    _purchasePriceController.text = fraction.purchasePrice.toStringAsFixed(2);
    _updateExpectedAmount();
  }

  /// Saves edited prices on the fraction (owners only). Returns an error message if that failed.
  Future<String?> _maybeUpdateFractionPrices(double newSellingPrice, double newPurchasePrice) async {
    final fraction = _selectedFraction;
    if (fraction == null) return null;

    final sellingChanged = (newSellingPrice - fraction.sellingPrice).abs() > 0.0001;
    final purchaseChanged = (newPurchasePrice - fraction.purchasePrice).abs() > 0.0001;

    if (!sellingChanged && !purchaseChanged) return null;

    final updated = await _itemProvider.updateFraction(
      fraction.id,
      fraction.name,
      fraction.ratio,
      newSellingPrice,
      newPurchasePrice,
      isUnit: fraction.isUnit,
    );

    if (!updated) {
      return _itemProvider.error ?? 'Failed to update prices';
    }

    setState(() {
      _selectedFraction = Fraction(
        id: fraction.id,
        name: fraction.name,
        ratio: fraction.ratio,
        sellingPrice: newSellingPrice,
        purchasePrice: newPurchasePrice,
        itemId: fraction.itemId,
        isUnit: fraction.isUnit,
      );
    });
    return null;
  }

  void _handleFractionChange(Fraction? value) {
    if (value == null) {
      setState(() {
        _selectedFraction = null;
        _expectedAmount = 0;
        _availableQuantity = 0;
      });
      _updatePriceFields(null);
      return;
    }

    setState(() {
      _selectedFraction = value;
      _expectedAmount = 0;
      _availableQuantity = 0;
    });
    _updatePriceFields(value);

    // Use Future.microtask to ensure the state update is complete before fetching
    Future.microtask(() async {
      try {
        await _fetchAvailableQuantity();
        if (mounted) {
          _updateExpectedAmount();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = 'Failed to update available quantity';
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isOwner = context.watch<AuthProvider>().isOwner;
    // Rebuild when stock changes (refresh, or queued sales syncing in the background)
    final assignedItems = context.watch<AvailableItemProvider>().availableItems;
    final appBar = AppBar(title: Text(l10n.sellItem));

    if (_isLoading) {
      return Scaffold(appBar: appBar, body: const Center(child: CircularProgressIndicator()));
    }

    if (_error != null || assignedItems.isEmpty) {
      return Scaffold(
        appBar: appBar,
        body: Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_error != null ? Icons.cloud_off_rounded : Icons.inventory_2_outlined, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _error ?? l10n.noItemsAssignedToYou,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _loadData(force: true),
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.retry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final availableQuantity = _availableQuantity;

    return Scaffold(
      appBar: appBar,
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadData(force: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<AvailableItem>(
                        value: _selectedAvailableItem,
                        decoration: InputDecoration(labelText: l10n.selectItem, border: const OutlineInputBorder()),
                        items:
                            assignedItems.map((availableItem) {
                              return DropdownMenuItem<AvailableItem>(
                                value: availableItem,
                                child: Text(availableItem.item!.name),
                              );
                            }).toList(),
                        onChanged: _isSubmitting ? null : _handleItemChange,
                        validator: (value) => value == null ? l10n.pleaseSelectItem : null,
                      ),
                      const SizedBox(height: 16),
                      if (_selectedAvailableItem != null)
                        DropdownButtonFormField<Fraction>(
                          value: _selectedFraction,
                          decoration: InputDecoration(labelText: l10n.selectUnit, border: const OutlineInputBorder()),
                          items:
                              _selectedAvailableItem!.item!.fractions?.map((fraction) {
                                return DropdownMenuItem<Fraction>(
                                  value: fraction,
                                  child: Text('${fraction.name} - \$${fraction.sellingPrice}'),
                                );
                              }).toList(),
                          onChanged: _isSubmitting ? null : _handleFractionChange,
                          validator: (value) => value == null ? l10n.pleaseSelectUnit : null,
                        ),
                      if (_selectedFraction != null) ...[
                        const SizedBox(height: 16),
                        CustomTextField(
                          controller: _sellingPriceController,
                          labelText: l10n.soldPriceLabel,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          enabled: !_isSubmitting,
                          onChanged: (_) => _updateExpectedAmount(),
                        ),
                        if (isOwner) ...[
                          const SizedBox(height: 16),
                          CustomTextField(
                            controller: _purchasePriceController,
                            labelText: l10n.purchasePrice,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            enabled: !_isSubmitting,
                          ),
                        ],
                      ],
                      const SizedBox(height: 16),
                      CustomTextField(
                        controller: _quantityController,
                        labelText: l10n.quantityLabel,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _updateExpectedAmount(),
                        enabled: !_isSubmitting,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.pleaseEnterQuantity;
                          }
                          final quantity = double.tryParse(value);
                          if (quantity == null) {
                            return l10n.pleaseEnterValidNumber;
                          }
                          if (quantity <= 0) {
                            return l10n.quantityMustBeGreaterThanZero;
                          }
                          if (quantity > availableQuantity) {
                            return l10n.availableQuantityIs(availableQuantity);
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.availableQuantityWithLoading(availableQuantity.toString()),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.expectedAmountWithCurrency(_expectedAmount.toStringAsFixed(2)),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedFraction != null && isOwner)
                        Text(
                          l10n.profitWithAmount('${l10n.currencySymbol}${_profit.toStringAsFixed(2)}'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      const SizedBox(height: 24),
                      CustomButton(
                        onPressed:
                            _isSubmitting
                                ? null
                                : () {
                                  _sellItem();
                                },
                        text: _isSubmitting ? l10n.processing : l10n.sellItem,
                        isLoading: _isSubmitting,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
