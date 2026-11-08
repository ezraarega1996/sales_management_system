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
        return const ItemsScreen();
      case 3:
        return const CategoriesScreen();
      case 4:
        return const UsersScreen();
      case 5:
        return const SubscriptionScreen();
      case 6:
        return const BoughtsScreen();
      case 7:
        return const AvailableItemsScreen();
      case 8:
        return const ShopsScreen();
      case 9:
        return const SummaryScreen();
      default:
        return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    // Indexes match _getScreen(): 1 = sales, 7 = available items, 8 = shops
    return DashboardView(
      isLoading: _isLoading,
      onRefresh: _loadDashboardData,
      onViewSales: () => _onItemTapped(1),
      onViewStock: () => _onItemTapped(7),
      onViewShops: () => _onItemTapped(8),
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
    return Drawer(
      child: ListView(
        // No top padding so the header fills the status bar area, but keep the last items
        // (Logout) above the phone's navigation bar so they can be tapped
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8),
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Text(l10n.menu, style: TextStyle(color: Colors.white, fontSize: 24)),
          ),
          ListTile(
            leading: Icon(Icons.dashboard),
            title: Text(l10n.dashboard),
            selected: _selectedIndex == 0,
            onTap: () {
              setState(() {
                _selectedIndex = 0;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.summarize),
            title: Text(l10n.summary),
            selected: _selectedIndex == 9,
            onTap: () {
              setState(() {
                _selectedIndex = 9;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.shop),
            title: Text(l10n.shops),
            selected: _selectedIndex == 8,
            onTap: () {
              setState(() {
                _selectedIndex = 8;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.people),
            title: Text(l10n.salesPerson),
            selected: _selectedIndex == 4,
            onTap: () {
              setState(() {
                _selectedIndex = 4;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.category),
            title: Text(l10n.categories),
            selected: _selectedIndex == 3,
            onTap: () {
              setState(() {
                _selectedIndex = 3;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.inventory),
            title: Text(l10n.items),
            selected: _selectedIndex == 2,
            onTap: () {
              setState(() {
                _selectedIndex = 2;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.shopping_basket),
            title: Text(l10n.storedItems),
            selected: _selectedIndex == 6,
            onTap: () {
              setState(() {
                _selectedIndex = 6;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.inventory_2),
            title: Text(l10n.availableItems),
            selected: _selectedIndex == 7,
            onTap: () {
              setState(() {
                _selectedIndex = 7;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.shopping_cart),
            title: Text(l10n.sales),
            selected: _selectedIndex == 1,
            onTap: () {
              setState(() {
                _selectedIndex = 1;
              });
              Navigator.pop(context);
            },
          ),

          ListTile(
            leading: Icon(Icons.card_membership),
            title: Text(l10n.subscription),
            selected: _selectedIndex == 5,
            onTap: () {
              setState(() {
                _selectedIndex = 5;
              });
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock, color: Colors.blue),
            title: const Text('Change Password'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
            },
          ),
          const Divider(),
          ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: Text(l10n.logout), onTap: _logout),
        ],
      ),
    );
  }
}
