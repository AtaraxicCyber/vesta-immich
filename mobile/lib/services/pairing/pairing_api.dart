import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// Client for the Cloudflare-hosted account/pairing endpoints. Deliberately
/// separate from Immich's generated openapi client: this talks to
/// vesta-vault.com, not the unit's own local Immich server, and the two
/// never share a base URL or an auth scheme.
class PairingApi {
  PairingApi({this.baseUrl = 'https://vesta-vault.com'});

  final String baseUrl;
  final _log = Logger('PairingApi');

  Future<PairingApiResult<void>> requestCode(String email) async {
    return _post('/api/auth/request-code', {'email': email}, (_) {});
  }

  Future<PairingApiResult<String>> verifyCode(String email, String code) async {
    return _post('/api/auth/verify-code', {'email': email, 'code': code}, (body) {
      final token = body['session_token'];
      if (token is! String || token.isEmpty) {
        throw const FormatException('missing session_token');
      }
      return token;
    });
  }

  Future<PairingApiResult<bool>> claim({required String sessionToken, required String claimToken}) async {
    return _post(
      '/api/pair/claim',
      {'session_token': sessionToken, 'claim_token': claimToken},
      (body) => body['already_confirmed'] == true,
    );
  }

  Future<PairingApiResult<T>> _post<T>(
    String path,
    Map<String, dynamic> payload,
    T Function(Map<String, dynamic> body) onOk,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      final body = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode < 200 || response.statusCode >= 300 || body['ok'] == false) {
        final message = body['error'] as String? ?? 'Request failed (${response.statusCode})';
        return PairingApiResult.failure(message);
      }

      return PairingApiResult.success(onOk(body));
    } catch (e) {
      _log.warning('$path failed', e);
      return const PairingApiResult.failure('Could not reach Vesta Vault. Check your connection and try again.');
    }
  }
}

class PairingApiResult<T> {
  const PairingApiResult.success(this.value) : error = null;
  const PairingApiResult.failure(this.error) : value = null;

  final T? value;
  final String? error;

  bool get isSuccess => error == null;
}
