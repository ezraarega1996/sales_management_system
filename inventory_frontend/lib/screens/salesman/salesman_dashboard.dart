import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/providers/sales_provider.dart';
import 'package:inventory_frontend/screens/auth/login_screen.dart';
import 'package:inventory_frontend/screens/salesman/sell_item_screen.dart';
import 'package:inventory_frontend/screens/salesman/view_sales_screen.dart';
import 'package:inventory_frontend/screens/available_items_screen.dart';
import 'package:inventory_frontend/screens/dashboard_view.dart';
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
        return const SellItemScreen();
      case 3:
        return const ViewSalesScreen();
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
    return Scaffold(
      appBar: AppBar(
        title: Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            // The dashboard header already greets the user by name
            return Text(_selectedIndex == 0 ? l10n.dashboard : authProvider.user?.name ?? l10n.salesmanDashboard);
          },
        ),
        actions: const [LanguageSelector()],
      ),
      drawer: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          return Drawer(
            child: ListView(
              // No top padding so the header fills the status bar area, but keep the last items
              // (Logout) above the phone's navigation bar so they can be tapped
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8),
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(color: Theme.of(context).primaryColor),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white,
                        child: Text(
                          authProvider.user?.name.substring(0, 1).toUpperCase() ?? 'S',
                          style: TextStyle(fontSize: 24, color: Theme.of(context).primaryColor),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        authProvider.user?.name ?? l10n.salesmanDashboard,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      Text(authProvider.user?.email ?? '', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dashboard, color: Colors.blue),
                  title: Text(l10n.dashboard),
                  selected: _selectedIndex == 0,
                  selectedColor: Colors.blue,
                  onTap: () {
                    setState(() => _selectedIndex = 0);
                    _loadDashboardData(); // refresh numbers after selling elsewhere
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.table_chart, color: Colors.teal),
                  title: Text(l10n.summary),
                  selected: _selectedIndex == 4,
                  selectedColor: Colors.teal,
                  onTap: () {
                    setState(() => _selectedIndex = 4);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_shopping_cart, color: Colors.orange),
                  title: Text(l10n.sellItem),
                  selected: _selectedIndex == 2,
                  selectedColor: Colors.orange,
                  onTap: () {
                    setState(() => _selectedIndex = 2);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2, color: Colors.green),
                  title: Text(l10n.availableItems),
                  selected: _selectedIndex == 1,
                  selectedColor: Colors.green,
                  onTap: () {
                    setState(() => _selectedIndex = 1);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.purple),
                  title: Text(l10n.salesHistory),
                  selected: _selectedIndex == 3,
                  selectedColor: Colors.purple,
                  onTap: () {
                    setState(() => _selectedIndex = 3);
                    Navigator.pop(context);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: Text(l10n.logout),
                  onTap: _logout,
                ),
              ],
            ),
          );
        },
      ),
      body: _getScreen(),
    );
  }
}
