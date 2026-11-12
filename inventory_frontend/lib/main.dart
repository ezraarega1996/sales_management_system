import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/providers/available_item_provider.dart';
import 'package:inventory_frontend/providers/basket_provider.dart';
import 'package:inventory_frontend/providers/bought_provider.dart';
import 'package:inventory_frontend/providers/business_provider.dart';
import 'package:inventory_frontend/providers/category_provider.dart';
import 'package:inventory_frontend/providers/item_provider.dart';
import 'package:inventory_frontend/providers/language_provider.dart';
import 'package:inventory_frontend/providers/sales_provider.dart';
import 'package:inventory_frontend/providers/shop_provider.dart';
import 'package:inventory_frontend/providers/user_provider.dart';
import 'package:inventory_frontend/screens/auth/login_screen.dart';
import 'package:inventory_frontend/screens/splash_screen.dart';
import 'package:inventory_frontend/services/business_service.dart';
import 'package:inventory_frontend/services/sale_outbox.dart';
import 'package:inventory_frontend/utils/api.dart';
import 'package:inventory_frontend/utils/connection_status.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final languageProvider = await LanguageProvider.create();
  final authProvider = AuthProvider();

  // Session rejected by the server (expired token): log out and go back to the login screen
  Api.onUnauthorized = () async {
    if (!authProvider.isAuthenticated) return;
    await authProvider.logout();
    navigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  };

  // Send queued sales as soon as the server is reachable again
  ConnectionStatus.instance.addListener(() {
    if (!ConnectionStatus.instance.isOffline) SaleOutbox.instance.sync();
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: languageProvider),
        ChangeNotifierProvider.value(value: authProvider),
        Provider(create: (_) => BusinessService()),
        ChangeNotifierProxyProvider<BusinessService, BusinessProvider>(
          create: (context) => BusinessProvider(context.read<BusinessService>()),
          update: (context, businessService, previous) => previous ?? BusinessProvider(businessService),
        ),
        ChangeNotifierProvider(create: (_) => SalesProvider()),
        ChangeNotifierProvider(create: (_) => ItemProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => BoughtProvider()),
        ChangeNotifierProvider(create: (_) => AvailableItemProvider()),
        ChangeNotifierProvider(create: (_) => ShopProvider()),
        ChangeNotifierProvider(create: (_) => BasketProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // On logout, forget everything the previous user loaded (sales, stock, prices, basket...), so the
    // next person signing in on this phone starts clean and never sees another user's data
    context.read<AuthProvider>().onLoggedOut = () {
      context.read<SalesProvider>().reset();
      context.read<AvailableItemProvider>().reset();
      context.read<BoughtProvider>().reset();
      context.read<BusinessProvider>().reset();
      context.read<CategoryProvider>().reset();
      context.read<ItemProvider>().reset();
      context.read<ShopProvider>().reset();
      context.read<UserProvider>().reset();
      context.read<BasketProvider>().clear();
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is a good moment to retry sales queued while offline
    if (state == AppLifecycleState.resumed) SaleOutbox.instance.sync();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageProvider>(
      builder: (context, languageProvider, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Inventory Management',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('am')],
          locale: languageProvider.locale,
          home: const SplashScreen(),
        );
      },
    );
  }
}
