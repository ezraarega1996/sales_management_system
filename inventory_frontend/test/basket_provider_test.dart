import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_frontend/models/available_item.dart';
import 'package:inventory_frontend/models/fraction.dart';
import 'package:inventory_frontend/models/item.dart';
import 'package:inventory_frontend/providers/basket_provider.dart';

Fraction fraction(String id, double ratio, double price, {double cost = 0, bool unit = false}) =>
    Fraction(id: id, name: id, ratio: ratio, sellingPrice: price, purchasePrice: cost, itemId: 'coke', isUnit: unit);

final bottle = fraction('Bottle', 1, 25, cost: 18, unit: true);
final crate = fraction('Crate', 24, 576, cost: 410);

AvailableItem stock({String id = 's1', String shopId = 'shop-1', double quantity = 30}) => AvailableItem(
  id: id,
  itemId: 'coke',
  businessId: 'b',
  shopId: shopId,
  quantity: quantity,
  soldPrice: 25,
  item: Item(id: 'coke', name: 'Coca-Cola', categoryId: 'c', fractions: [bottle, crate]),
);

void main() {
  late BasketProvider basket;
  setUp(() => basket = BasketProvider());

  test('adding the same item and unit increases one line', () {
    expect(basket.add(stock(), bottle), BasketResult.ok);
    expect(basket.add(stock(), bottle), BasketResult.ok);
    expect(basket.lineCount, 1);
    expect(basket.lines.single.quantity, 2);
    expect(basket.total, 50);
  });

  test('different units of the same item are separate lines sharing the stock', () {
    final s = stock(quantity: 30);
    basket.add(s, crate); // 24 units
    basket.add(s, bottle, quantity: 6); // 6 units -> 30 used
    expect(basket.lineCount, 2);
    expect(basket.unitsInBasket(s.id), 30);
    expect(basket.remainingFor(s, bottle), 0);
    expect(basket.add(s, bottle), BasketResult.notEnoughStock);
  });

  test('cannot add more than the stock left', () {
    final s = stock(quantity: 30);
    expect(basket.add(s, crate, quantity: 2), BasketResult.notEnoughStock);
    expect(basket.isEmpty, isTrue);
    expect(basket.remainingFor(s, crate), closeTo(1.25, 1e-9));
  });

  test('setQuantity respects stock, and 0 removes the line', () {
    final s = stock(quantity: 10);
    basket.add(s, bottle);
    final line = basket.lines.single;
    expect(basket.setQuantity(line, 10), BasketResult.ok);
    expect(basket.setQuantity(line, 11), BasketResult.notEnoughStock);
    expect(basket.lines.single.quantity, 10);
    expect(basket.setQuantity(basket.lines.single, 0), BasketResult.ok);
    expect(basket.isEmpty, isTrue);
  });

  test('a basket belongs to one shop', () {
    basket.add(stock(shopId: 'shop-1'), bottle);
    expect(basket.add(stock(id: 's2', shopId: 'shop-2'), bottle), BasketResult.otherShop);
    expect(basket.shopId, 'shop-1');
  });

  test('changeUnit is refused when the bigger unit does not fit in stock', () {
    final s = stock(quantity: 30);
    basket.add(s, bottle, quantity: 2);
    final bottles = basket.lines.single;
    // 2 bottles -> 2 crates = 48 units > 30 in stock
    expect(basket.changeUnit(bottles, crate), BasketResult.notEnoughStock);
    expect(basket.lines.single.fraction.id, 'Bottle');
  });

  test('changeUnit merges when stock allows', () {
    final s = stock(quantity: 100);
    basket.add(s, bottle, quantity: 2);
    basket.add(s, crate);
    final bottles = basket.lines.firstWhere((l) => l.fraction.id == 'Bottle');
    // 2 bottles -> 2 crates (48 units) + existing 1 crate (24) = 72 units <= 100
    expect(basket.changeUnit(bottles, crate), BasketResult.ok);
    expect(basket.lineCount, 1);
    expect(basket.lines.single.quantity, 3);
  });

  test('price override changes amount and profit', () {
    basket.add(stock(), bottle, quantity: 2);
    final line = basket.lines.single;
    expect(line.profit, 14); // (25 - 18) * 2
    basket.setPrice(line, 30);
    expect(basket.lines.single.amount, 60);
    expect(basket.lines.single.profit, 24);
  });

  test('refreshStock keeps lines pointing at the latest stock numbers', () {
    basket.add(stock(quantity: 5), bottle);
    basket.refreshStock([stock(quantity: 2)]);
    expect(basket.remainingFor(basket.lines.single.stock, bottle), 1);
  });
}
