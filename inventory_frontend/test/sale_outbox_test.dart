import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_frontend/services/sale_outbox.dart';
import 'package:inventory_frontend/utils/api.dart';

class MemoryStore implements OutboxStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String userId) async => data[userId];
  @override
  Future<void> write(String userId, String value) async => data[userId] = value;
}

/// Fake server: records what it receives and can be told to fail.
class FakeServer {
  final List<(String, Map<String, dynamic>)> received = [];
  final Set<String> seenClientIds = {};
  Object? failWith;

  Future<dynamic> send(String endpoint, Map<String, dynamic> payload) async {
    final error = failWith;
    if (error != null) throw error;
    received.add((endpoint, payload));
    seenClientIds.add(payload['clientId'] as String);
    final lines = (payload['lines'] as List?) ?? [payload];
    return [
      for (var i = 0; i < lines.length; i++) {'id': 'server-${received.length}-$i'},
    ];
  }
}

void main() {
  late MemoryStore store;
  late FakeServer server;
  late SaleOutbox outbox;

  Future<PendingSale> enqueue({Map<String, double> stockUnits = const {'stock-1': 2}}) => outbox.enqueueBasket(
    shopId: 'shop-1',
    lines: [
      {'itemId': 'item-1', 'fractionId': 'f-1', 'quantity': 2, 'amount': 50},
      {'itemId': 'item-2', 'fractionId': 'f-2', 'quantity': 1, 'amount': 140},
    ],
    stockUnits: stockUnits,
    title: 'Coca-Cola ×2, Sugar ×1',
  );

  setUp(() async {
    store = MemoryStore();
    server = FakeServer();
    outbox = SaleOutbox(sender: server.send, store: store, retryInterval: null);
    await outbox.switchUser('user-1');
  });

  test('enqueue builds a basket payload with clientId and soldTime and persists it', () async {
    final sale = await enqueue();

    expect(sale.payload['clientId'], sale.clientId);
    expect(sale.payload['soldTime'], isNotNull);
    expect(sale.payload['shopId'], 'shop-1');
    expect(sale.endpoint, 'sales/batch');
    expect(sale.itemCount, 2);
    expect(sale.amount, 190);

    // A fresh outbox for the same user loads it back (survives an app restart)
    final reloaded = SaleOutbox(sender: server.send, store: store, retryInterval: null);
    await reloaded.switchUser('user-1');
    expect(reloaded.pending.single.clientId, sale.clientId);
    expect(reloaded.pending.single.stockUnits, {'stock-1': 2});
  });

  test('sync sends baskets oldest first to the batch endpoint and removes them', () async {
    final first = await enqueue();
    final second = await enqueue();
    final synced = <SyncedSale>[];
    outbox.synced.listen(synced.add);

    final sent = await outbox.sync();
    await Future<void>.delayed(Duration.zero);

    expect(sent, 2);
    expect(server.received.map((r) => r.$1), ['sales/batch', 'sales/batch']);
    expect(server.received.map((r) => r.$2['clientId']), [first.clientId, second.clientId]);
    expect(outbox.pending, isEmpty);
    expect(synced, hasLength(2));
    expect(synced.first.serverResponse, hasLength(2), reason: 'one created line per basket line');
  });

  test('entries saved by the previous app version (single sales) still load and sync', () async {
    store.data['user-1'] = jsonEncode([
      {
        'clientId': 'old-1',
        'payload': {'itemId': 'i', 'fractionId': 'f', 'quantity': 1, 'amount': 25, 'clientId': 'old-1'},
        'availableItemId': 'stock-9',
        'units': 24,
        'itemName': 'Coca-Cola',
        'fractionName': 'Crate',
        'createdAt': DateTime(2026).toIso8601String(),
        'error': null,
      },
    ]);
    await outbox.switchUser('user-1');

    final old = outbox.pending.single;
    expect(old.endpoint, 'sales');
    expect(old.title, 'Coca-Cola Crate');
    expect(outbox.pendingUnitsFor('stock-9'), 24);
    expect(await outbox.sync(), 1);
    expect(server.received.single.$1, 'sales');
  });

  test('network failure keeps the basket queued; retry keeps the same clientId', () async {
    final sale = await enqueue();
    server.failWith = const OfflineException();

    expect(await outbox.sync(), 0);
    expect(outbox.pending, hasLength(1));
    expect(outbox.isPending(sale.clientId), isTrue);

    server.failWith = null;
    expect(await outbox.sync(), 1);
    expect(outbox.isPending(sale.clientId), isFalse);
    expect(server.seenClientIds, {sale.clientId});
  });

  test('permanent rejection (4xx) marks the basket failed instead of retrying forever', () async {
    await enqueue();
    server.failWith = const ApiException(400, 'Not enough Sugar in stock');

    await outbox.sync();
    expect(outbox.pending, isEmpty);
    expect(outbox.failed.single.error, 'Not enough Sugar in stock');

    server.failWith = null;
    await outbox.sync();
    expect(server.received, isEmpty, reason: 'failed sales are not resent automatically');
  });

  test('server errors (5xx) and expired sessions (401) keep the basket queued', () async {
    await enqueue();
    for (final status in [500, 401]) {
      server.failWith = ApiException(status, 'error');
      await outbox.sync();
      expect(outbox.pending, hasLength(1), reason: 'status $status');
      expect(outbox.failed, isEmpty, reason: 'status $status');
    }
  });

  test('a failed basket can be retried or discarded', () async {
    final sale = await enqueue();
    server.failWith = const ApiException(400, 'rejected');
    await outbox.sync();

    server.failWith = null;
    await outbox.retry(sale.clientId);
    expect(outbox.failed, isEmpty);
    expect(server.received, hasLength(1));

    final other = await enqueue();
    server.failWith = const ApiException(400, 'rejected');
    await outbox.sync();
    await outbox.discard(other.clientId);
    expect(outbox.hasUnsynced, isFalse);
  });

  test('pendingUnitsFor sums all unsynced baskets per stock row, ignoring failed ones', () async {
    await enqueue(stockUnits: {'stock-1': 2, 'stock-2': 1});
    await enqueue(stockUnits: {'stock-1': 3});
    expect(outbox.pendingUnitsFor('stock-1'), 5);
    expect(outbox.pendingUnitsFor('stock-2'), 1);
    expect(outbox.pendingUnitsFor('other'), 0);

    server.failWith = const ApiException(400, 'rejected');
    await outbox.sync();
    expect(outbox.pendingUnitsFor('stock-1'), 0, reason: 'rejected sales give the stock back');
  });

  test('each user has their own queue', () async {
    await enqueue();
    await outbox.switchUser('user-2');
    expect(outbox.pending, isEmpty);
    await outbox.switchUser('user-1');
    expect(outbox.pending, hasLength(1));
  });
}
