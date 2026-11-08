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
  final List<Map<String, dynamic>> received = [];
  final Set<String> seenClientIds = {};
  Object? failWith;

  Future<dynamic> send(Map<String, dynamic> payload) async {
    final error = failWith;
    if (error != null) throw error;
    received.add(payload);
    seenClientIds.add(payload['clientId'] as String);
    return {'id': 'server-${received.length}', ...payload};
  }
}

void main() {
  late MemoryStore store;
  late FakeServer server;
  late SaleOutbox outbox;

  Future<PendingSale> enqueue({double units = 2}) => outbox.enqueue(
        payload: {'itemId': 'item-1', 'fractionId': 'f-1', 'quantity': 2, 'amount': 50, 'shopId': 'shop-1'},
        availableItemId: 'stock-1',
        units: units,
        itemName: 'Coca-Cola',
        fractionName: 'Bottle',
      );

  setUp(() async {
    store = MemoryStore();
    server = FakeServer();
    outbox = SaleOutbox(sender: server.send, store: store, retryInterval: null);
    await outbox.switchUser('user-1');
  });

  test('enqueue adds a clientId and soldTime and persists the sale', () async {
    final sale = await enqueue();

    expect(sale.payload['clientId'], isNotEmpty);
    expect(sale.payload['soldTime'], isNotNull);
    expect(outbox.pending, hasLength(1));

    // A fresh outbox for the same user loads it back (survives an app restart)
    final reloaded = SaleOutbox(sender: server.send, store: store, retryInterval: null);
    await reloaded.switchUser('user-1');
    expect(reloaded.pending.single.clientId, sale.clientId);
  });

  test('sync sends queued sales oldest first and removes them', () async {
    final first = await enqueue();
    final second = await enqueue();
    final synced = <SyncedSale>[];
    outbox.synced.listen(synced.add);

    final sent = await outbox.sync();
    await Future<void>.delayed(Duration.zero);

    expect(sent, 2);
    expect(server.received.map((p) => p['clientId']), [first.clientId, second.clientId]);
    expect(outbox.pending, isEmpty);
    expect(synced, hasLength(2));
  });

  test('network failure keeps the sale queued for a later retry', () async {
    await enqueue();
    server.failWith = const OfflineException();

    expect(await outbox.sync(), 0);
    expect(outbox.pending, hasLength(1));
    expect(outbox.failed, isEmpty);

    server.failWith = null;
    expect(await outbox.sync(), 1);
    expect(outbox.pending, isEmpty);
  });

  test('a retried sale keeps the same clientId so the server can deduplicate it', () async {
    final sale = await enqueue();
    server.failWith = const OfflineException();
    await outbox.sync();
    server.failWith = null;
    await outbox.sync();

    expect(server.seenClientIds, {sale.clientId});
  });

  test('permanent rejection (4xx) marks the sale failed instead of retrying forever', () async {
    await enqueue();
    server.failWith = const ApiException(400, 'Not enough quantity available');

    await outbox.sync();
    expect(outbox.pending, isEmpty);
    expect(outbox.failed.single.error, 'Not enough quantity available');

    // Failed sales are not resent by later syncs
    server.failWith = null;
    await outbox.sync();
    expect(server.received, isEmpty);
  });

  test('server errors (5xx) and expired sessions (401) keep the sale queued', () async {
    await enqueue();
    for (final status in [500, 401]) {
      server.failWith = ApiException(status, 'error');
      await outbox.sync();
      expect(outbox.pending, hasLength(1), reason: 'status $status');
      expect(outbox.failed, isEmpty, reason: 'status $status');
    }
  });

  test('a failed sale can be retried or discarded', () async {
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

  test('pendingUnitsFor sums only unsynced, non-failed sales of that stock row', () async {
    await enqueue(units: 2);
    await enqueue(units: 3);
    expect(outbox.pendingUnitsFor('stock-1'), 5);
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
