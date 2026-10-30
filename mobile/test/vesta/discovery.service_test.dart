import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immich_mobile/vesta/discovery.service.dart';

void main() {
  late Uri requested;

  VestaDiscoveryService serviceReturning(int status, String body) {
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response(body, status);
    });
    return VestaDiscoveryService(() => client, endpoint: 'https://cloud.example.test/api/v1/discover');
  }

  Matcher throwsDiscovery(VestaDiscoveryError error) =>
      throwsA(isA<VestaDiscoveryException>().having((e) => e.error, 'error', error));

  test('returns the server URL and sends the trimmed email', () async {
    final sut = serviceReturning(200, '{"serverUrl":"https://family-a.vesta-vault.com"}');

    expect(await sut.discover(' Parent@Family-A.test '), 'https://family-a.vesta-vault.com');
    expect(requested.toString(), 'https://cloud.example.test/api/v1/discover?email=Parent%40Family-A.test');
  });

  test('maps 404 to notFound', () {
    expect(serviceReturning(404, '{"error":"not_found"}').discover('x@y.test'), throwsDiscovery(.notFound));
  });

  test('maps 400 to invalidEmail', () {
    expect(serviceReturning(400, '{"error":"invalid_email"}').discover('nope'), throwsDiscovery(.invalidEmail));
  });

  test('maps server errors to unavailable', () {
    expect(serviceReturning(500, 'oops').discover('x@y.test'), throwsDiscovery(.unavailable));
  });

  test('rejects a 200 without a usable http(s) server URL', () async {
    for (final body in ['not json', '{}', '{"serverUrl":42}', '{"serverUrl":"javascript:alert(1)"}', '[]']) {
      await expectLater(serviceReturning(200, body).discover('x@y.test'), throwsDiscovery(.unavailable), reason: body);
    }
  });

  test('maps network failures to unavailable', () {
    final sut = VestaDiscoveryService(
      () => MockClient((_) => throw http.ClientException('offline')),
      endpoint: 'https://cloud.example.test/api/v1/discover',
    );
    expect(sut.discover('x@y.test'), throwsDiscovery(.unavailable));
  });
}
