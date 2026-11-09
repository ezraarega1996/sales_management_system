import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inventory_frontend/models/available_item.dart';
import 'package:inventory_frontend/models/category.dart';
import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/models/item.dart';
import 'package:inventory_frontend/models/sold_item.dart';
import 'package:inventory_frontend/providers/auth_provider.dart';
import 'package:inventory_frontend/providers/available_item_provider.dart';
import 'package:inventory_frontend/providers/basket_provider.dart';
import 'package:inventory_frontend/providers/category_provider.dart';
import 'package:inventory_frontend/providers/sales_provider.dart';
import 'package:inventory_frontend/screens/salesman/pos_screen.dart';
import 'package:inventory_frontend/services/sale_outbox.dart';

// Stand-ins that serve fixed data instead of calling the server.
class FakeStock extends AvailableItemProvider {
  FakeStock(this.items, SaleOutbox outbox) : super(outbox: outbox);
  final List<AvailableItem> items;
  @override
  List<AvailableItem> get availableItems => items;
  @override
  Future<void> fetchAvailableItems({String? shopId, bool force = true}) async {}
}

class FakeSales extends SalesProvider {
  FakeSales(SaleOutbox outbox) : super(outbox: outbox);
  @override
  List<SoldItem> get sales => const [];
  @override
  Future<void> fetchUserSales() async {}
}

class FakeCategories extends CategoryProvider {
  @override
  List<Category> get categories => [Category(id: 'bev', name: 'Beverages'), Category(id: 'food', name: 'Food')];
  @override
  Future<void> fetchCategories() async {}
}

AvailableItem stock(String id, String name, String category, List<Fraction> fractions, double quantity) =>
    AvailableItem(
      id: 'stock-$id',
      itemId: id,
      businessId: 'b',
      shopId: 'shop-1',
      quantity: quantity,
      soldPrice: fractions.first.sellingPrice,
      item: Item(id: id, name: name, categoryId: category, fractions: fractions),
    );

Fraction unit(String item, String name, double ratio, double price, {bool isUnit = false}) => Fraction(
  id: '$item-$name',
  name: name,
  ratio: ratio,
  sellingPrice: price,
  purchasePrice: 0,
  itemId: item,
  isUnit: isUnit,
);

void main() {
  late BasketProvider basket;

  /// [fillers] adds that many extra items before "Zebra Juice" so the list has to scroll.
  Future<void> pumpPos(WidgetTester tester, {int fillers = 0}) async {
    SharedPreferences.setMockInitialValues({});
    final outbox = SaleOutbox(retryInterval: null);
    basket = BasketProvider();
    final items = [
      stock('coke', 'Coca-Cola', 'bev', [
        unit('coke', 'Bottle', 1, 25, isUnit: true),
        unit('coke', 'Crate', 24, 576),
      ], 50),
      stock('sugar', 'Sugar', 'food', [unit('sugar', 'kg', 1, 140, isUnit: true)], 20),
      for (var i = 0; i < fillers; i++)
        stock('f$i', 'Filler $i', 'food', [unit('f$i', 'Piece', 1, 10, isUnit: true)], 10),
      if (fillers > 0) stock('zebra', 'Zebra Juice', 'bev', [unit('zebra', 'Bottle', 1, 30, isUnit: true)], 10),
    ];
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ChangeNotifierProvider<AvailableItemProvider>(create: (_) => FakeStock(items, outbox)),
          ChangeNotifierProvider<SalesProvider>(create: (_) => FakeSales(outbox)),
          ChangeNotifierProvider<CategoryProvider>(create: (_) => FakeCategories()),
          ChangeNotifierProvider<BasketProvider>.value(value: basket),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('am')],
          home: PosScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder search() => find.byType(TextField).first;
  Finder addButtonOf(String name) =>
      find.descendant(of: find.widgetWithText(Card, name), matching: find.byIcon(Icons.add));

  testWidgets('search, add, and the search clears and keeps focus for the next item', (tester) async {
    await pumpPos(tester);

    await tester.enterText(search(), 'coca');
    await tester.pumpAndSettle();
    expect(find.text('Sugar'), findsNothing, reason: 'search filters the list');

    await tester.tap(addButtonOf('Coca-Cola'));
    await tester.pumpAndSettle();

    expect(basket.lines.single.itemName, 'Coca-Cola');
    expect(tester.widget<TextField>(search()).controller!.text, isEmpty);
    expect(tester.widget<TextField>(search()).focusNode!.hasFocus, isTrue);
    expect(find.text('Sugar'), findsOneWidget, reason: 'full list is back for the next item');
  });

  testWidgets('pressing enter adds the item when the search matches exactly one', (tester) async {
    await pumpPos(tester);

    await tester.enterText(search(), 'sug');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(basket.lines.single.itemName, 'Sugar');
    expect(basket.lines.single.quantity, 1);
  });

  testWidgets('long-press asks how many; quick ×12 adds 12 at once', (tester) async {
    await pumpPos(tester);

    await tester.longPress(addButtonOf('Coca-Cola'));
    await tester.pumpAndSettle();
    expect(find.text('Coca-Cola · Bottle'), findsOneWidget);

    await tester.tap(find.text('×12'));
    await tester.pumpAndSettle();
    expect(basket.lines.single.quantity, 12);
  });

  testWidgets('typing more than the stock left is refused with a message', (tester) async {
    await pumpPos(tester);

    await tester.longPress(addButtonOf('Sugar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '999');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(basket.isEmpty, isTrue);
    expect(find.textContaining('Not enough stock'), findsOneWidget);
  });

  Finder minusOf(String name) =>
      find.descendant(of: find.widgetWithText(Card, name), matching: find.widgetWithIcon(IconButton, Icons.remove));
  bool enabled(WidgetTester tester, Finder button) => tester.widget<IconButton>(button).onPressed != null;
  Finder badgeOf(String name) => find.descendant(of: find.widgetWithText(Card, name), matching: find.byType(Badge));

  testWidgets('every row always shows − and +; − is disabled until the item is in the basket', (tester) async {
    await pumpPos(tester);

    expect(minusOf('Coca-Cola'), findsOneWidget);
    expect(minusOf('Sugar'), findsOneWidget);
    expect(enabled(tester, minusOf('Coca-Cola')), isFalse);

    await tester.tap(addButtonOf('Coca-Cola'));
    await tester.tap(addButtonOf('Coca-Cola'));
    await tester.pumpAndSettle();
    expect(basket.lines.single.quantity, 2);
    expect(tester.widget<Badge>(badgeOf('Coca-Cola')).isLabelVisible, isTrue);
    expect(find.descendant(of: badgeOf('Coca-Cola'), matching: find.text('2')), findsOneWidget);

    await tester.tap(minusOf('Coca-Cola'));
    await tester.pumpAndSettle();
    expect(basket.lines.single.quantity, 1);

    await tester.tap(minusOf('Coca-Cola'));
    await tester.pumpAndSettle();
    expect(basket.isEmpty, isTrue);
    expect(minusOf('Coca-Cola'), findsOneWidget, reason: '− stays visible');
    expect(enabled(tester, minusOf('Coca-Cola')), isFalse);
    expect(tester.widget<Badge>(badgeOf('Coca-Cola')).isLabelVisible, isFalse);
  });

  testWidgets('− on a searched item also clears the search and keeps the keyboard up', (tester) async {
    await pumpPos(tester);
    await tester.tap(addButtonOf('Coca-Cola'));
    await tester.tap(addButtonOf('Coca-Cola'));
    await tester.pumpAndSettle();

    await tester.enterText(search(), 'coca');
    await tester.pumpAndSettle();
    await tester.tap(minusOf('Coca-Cola'));
    await tester.pumpAndSettle();

    expect(basket.lines.single.quantity, 1);
    expect(tester.widget<TextField>(search()).controller!.text, isEmpty);
    expect(tester.widget<TextField>(search()).focusNode!.hasFocus, isTrue);
  });

  testWidgets('the item just added stays in view (scrolled to and highlighted) after the search clears', (
    tester,
  ) async {
    await pumpPos(tester, fillers: 15);
    expect(find.text('Zebra Juice').hitTestable(), findsNothing, reason: 'starts below the fold');

    await tester.enterText(search(), 'zebra');
    await tester.pumpAndSettle();
    await tester.tap(addButtonOf('Zebra Juice'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(search()).controller!.text, isEmpty);
    expect(find.text('Filler 14'), findsOneWidget, reason: 'full list is back (neighbouring row shown)');
    expect(find.text('Zebra Juice').hitTestable(), findsOneWidget, reason: 'scrolled back into view');
    final card = tester.widget<Card>(find.widgetWithText(Card, 'Zebra Juice'));
    final context = tester.element(find.widgetWithText(Card, 'Zebra Juice'));
    expect(card.color, Theme.of(context).colorScheme.primaryContainer, reason: 'highlighted');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Card>(find.widgetWithText(Card, 'Zebra Juice')).color,
      isNot(Theme.of(context).colorScheme.primaryContainer),
    );
  });

  testWidgets('tapping anywhere on the row adds one', (tester) async {
    await pumpPos(tester);

    await tester.tap(find.text('Sugar'));
    await tester.pumpAndSettle();
    expect(basket.lines.single.itemName, 'Sugar');
  });
}
