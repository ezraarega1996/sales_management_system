import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/providers/business_provider.dart';
import 'package:inventory_frontend/providers/sales_provider.dart';
import 'package:inventory_frontend/screens/auth/login_screen.dart';
import 'package:inventory_frontend/screens/owner/categories_screen.dart';
import 'package:inventory_frontend/screens/owner/items_screen.dart';
import 'package:inventory_frontend/screens/owner/sales_screen.dart';
import 'package:inventory_frontend/screens/auth/change_password_screen.dart';
import 'package:inventory_frontend/screens/owner/subscription_screen.dart';
import 'package:inventory_frontend/screens/owner/users_screen.dart';
import 'package:inventory_frontend/screens/owner/boughts_screen.dart';
import 'package:inventory_frontend/screens/available_items_screen.dart';
import 'package:inventory_frontend/screens/owner/shops_screen.dart';
import 'package:inventory_frontend/screens/dashboard_view.dart';
import 'package:inventory_frontend/screens/summary_screen.dart';
import 'package:inventory_frontend/screens/salesman/pos_screen.dart';
import 'package:inventory_frontend/widgets/app_drawer.dart';
import 'package:inventory_frontend/widgets/language_selector.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  int _selectedIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Defer until after the first frame: the providers call notifyListeners()
    // synchronously, which is not allowed while the widget tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboardData());
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    final salesProvider = context.read<SalesProvider>();
    final authProvider = context.read<AuthProvider>();
    final businessProvider = context.read<BusinessProvider>();

    try {
      await Future.wait([
        salesProvider.fetchDashboardStats(),
        salesProvider.fetchTodaySales(),
        if (authProvider.user?.businessId != null) businessProvider.loadCurrentBusiness(authProvider.user!.businessId!),
      ]);
    } catch (_) {
      // Providers already track error state.
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Back on the dashboard after selling or buying elsewhere: refresh the numbers
    if (index == 0) _loadDashboardData();
  }

  Future<void> _logout() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.logout();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Widget _getScreen() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboard();
      case 1:
        return const SalesScreen();
      case 2:
        return const ItemsScreen(showAppBar: false);
      case 3:
        return const CategoriesScreen(showAppBar: false);
      case 4:
        return const UsersScreen(showAppBar: false);
      case 5:
        return const SubscriptionScreen();
      case 6:
        return const BoughtsScreen(showAppBar: false);
      case 7:
        return const AvailableItemsScreen();
      case 8:
        return const ShopsScreen(showAppBar: false);
      case 9:
        return const SummaryScreen();
      case 10:
        // Owners sell too; the dashboard provides the app bar
        return const PosScreen(showAppBar: false);
      default:
        return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    // Indexes match _getScreen(): 1 = sales, 7 = available items, 8 = shops, 10 = sell
    return DashboardView(
      isLoading: _isLoading,
      onRefresh: _loadDashboardData,
      onViewSales: () => _onItemTapped(1),
      onViewStock: () => _onItemTapped(7),
      onViewShops: () => _onItemTapped(8),
      onSell: () => _onItemTapped(10),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BusinessProvider>(
      builder: (context, businessProvider, child) {
        final business = businessProvider.currentBusiness;

        // Back on another tab returns to the dashboard instead of closing the app (and losing a basket)
        return PopScope(
          canPop: _selectedIndex == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => _selectedIndex = 0);
          },
          child: Scaffold(
            appBar: AppBar(
              // The dashboard header already shows the business name
              title: Text(
                _selectedIndex == 0 ? AppLocalizations.of(context)!.dashboard : business?.name ?? 'Owner Dashboard',
              ),
              actions: const [LanguageSelector()],
            ),
            drawer: _buildDrawer(),
            body: _getScreen(),
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    final l10n = AppLocalizations.of(context)!;
    // Indexes match _getScreen()
    return AppDrawer(
      selectedIndex: _selectedIndex,
      onSelect: _onItemTapped,
      onLogout: _logout,
      onChangePassword:
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
      sections: [
        AppDrawerSection(
          items: [
            AppDrawerItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: l10n.dashboard, index: 0),
            AppDrawerItem(icon: Icons.summarize_outlined, selectedIcon: Icons.summarize, label: l10n.summary, index: 9),
          ],
        ),
        AppDrawerSection(
          title: l10n.drawerSectionSales,
          items: [
            AppDrawerItem(icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, label: l10n.sellItem, index: 10),
            AppDrawerItem(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: l10n.sales, index: 1),
          ],
        ),
        AppDrawerSection(
          title: l10n.drawerSectionInventory,
          items: [
            AppDrawerItem(icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: l10n.availableItems, index: 7),
            AppDrawerItem(icon: Icons.local_shipping_outlined, selectedIcon: Icons.local_shipping, label: l10n.storedItems, index: 6),
            AppDrawerItem(icon: Icons.sell_outlined, selectedIcon: Icons.sell, label: l10n.items, index: 2),
            AppDrawerItem(icon: Icons.category_outlined, selectedIcon: Icons.category, label: l10n.categories, index: 3),
          ],
        ),
        AppDrawerSection(
          title: l10n.drawerSectionBusiness,
          items: [
            AppDrawerItem(icon: Icons.storefront_outlined, selectedIcon: Icons.storefront, label: l10n.shops, index: 8),
            AppDrawerItem(icon: Icons.people_outline, selectedIcon: Icons.people, label: l10n.salesPerson, index: 4),
            AppDrawerItem(icon: Icons.workspace_premium_outlined, selectedIcon: Icons.workspace_premium, label: l10n.subscription, index: 5),
          ],
        ),
      ],
    );
  }
}
