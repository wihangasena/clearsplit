import 'package:flutter_test/flutter_test.dart';
import 'package:buddysplit_flutter/backend_client.dart';

void main() {
  test('throws BackendClientException when backend is unreachable', () async {
    // Point at a closed port so the request fails fast.
    final client = BackendClient(baseUrl: 'http://127.0.0.1:1');
    expect(
      () => client.fetchAccounts(),
      throwsA(isA<BackendClientException>()),
    );
    client.dispose();
  });
}
