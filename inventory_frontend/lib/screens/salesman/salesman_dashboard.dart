import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/providers/sales_provider.dart';
import 'package:inventory_frontend/screens/auth/change_password_screen.dart';
import 'package:inventory_frontend/screens/auth/login_screen.dart';
import 'package:inventory_frontend/screens/salesman/pos_screen.dart';
import 'package:inventory_frontend/screens/salesman/view_sales_screen.dart';
import 'package:inventory_frontend/screens/available_items_screen.dart';
import 'package:inventory_frontend/screens/owner/boughts_screen.dart';
import 'package:inventory_frontend/screens/dashboard_view.dart';
import 'package:inventory_frontend/widgets/app_drawer.dart';
import 'package:inventory_frontend/widgets/language_selector.dart';
import 'package:inventory_frontend/screens/summary_screen.dart';
import 'package:inventory_frontend/services/sale_outbox.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SalesmanDashboard extends StatefulWidget {
  const SalesmanDashboard({super.key});

  @override
  State<SalesmanDashboard> createState() => _SalesmanDashboardState();
}

class _SalesmanDashboardState extends State<SalesmanDashboard> {
  int _selectedIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Load after the first frame: providers notify listeners, which isn't allowed during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboardData();
    });
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    final salesProvider = context.read<SalesProvider>();
    // Show what we already have (or the saved copy) instead of a spinner
    setState(() {
      _isLoading = salesProvider.dashboardStats == null;
    });

    try {
      // The cards only need the stats; the full sales list is loaded by Sales History
      await salesProvider.fetchDashboardStats();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.failedToLoadDashboard(e.toString()))));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    if (!mounted) return;
    final outbox = SaleOutbox.instance;
    if (outbox.hasUnsynced) {
      final l10n = AppLocalizations.of(context)!;
      final count = outbox.pending.length + outbox.failed.length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(l10n.unsyncedLogoutTitle),
              content: Text(l10n.unsyncedLogoutBody(count)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
                TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.logoutAnyway)),
              ],
            ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      await authProvider.logout();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.failedToLogout(e.toString()))));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _getScreen() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboard();
      case 1:
        return const AvailableItemsScreen();
      case 2:
        return const PosScreen(showAppBar: false);
      case 3:
        return const ViewSalesScreen();
      case 5:
        // What came into the shop (read-only, no prices for salesmen)
        return const BoughtsScreen(showAppBar: false);
      case 4:
        final authProvider = context.read<AuthProvider>();
        final shopId = authProvider.user?.shopId ?? authProvider.user?.shop?.id;

        return SummaryScreen(fixedShopId: shopId, allowShopSwitch: false);
      default:
        return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    // Same dashboard as the owner; the server returns this salesman's own numbers.
    // Indexes match _getScreen(): 1 = available items, 2 = sell, 3 = sales history
    return DashboardView(
      isLoading: _isLoading,
      onRefresh: _loadDashboardData,
      onViewSales: () => setState(() => _selectedIndex = 3),
      onViewStock: () => setState(() => _selectedIndex = 1),
      onSell: () => setState(() => _selectedIndex = 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Back on another tab returns to the dashboard instead of closing the app (and losing a basket)
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selectedIndex = 0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              // The dashboard header already greets the user by name
              return Text(_selectedIndex == 0 ? l10n.dashboard : authProvider.user?.name ?? l10n.salesmanDashboard);
            },
          ),
          actions: const [LanguageSelector()],
        ),
        // Indexes match _getScreen()
        drawer: AppDrawer(
          selectedIndex: _selectedIndex,
          onSelect: (index) {
            setState(() => _selectedIndex = index);
            if (index == 0) _loadDashboardData(); // refresh numbers after selling elsewhere
          },
          onLogout: _logout,
          onChangePassword:
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
          sections: [
            AppDrawerSection(
              items: [
                AppDrawerItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: l10n.dashboard, index: 0),
                AppDrawerItem(icon: Icons.summarize_outlined, selectedIcon: Icons.summarize, label: l10n.summary, index: 4),
              ],
            ),
            AppDrawerSection(
              title: l10n.drawerSectionSales,
              items: [
                AppDrawerItem(icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, label: l10n.sellItem, index: 2),
                AppDrawerItem(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: l10n.salesHistory, index: 3),
              ],
            ),
            AppDrawerSection(
              title: l10n.drawerSectionInventory,
              items: [
                AppDrawerItem(icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: l10n.availableItems, index: 1),
                AppDrawerItem(icon: Icons.local_shipping_outlined, selectedIcon: Icons.local_shipping, label: l10n.storedItems, index: 5),
              ],
            ),
          ],
        ),
        body: _getScreen(),
      ),
    );
  }
}
