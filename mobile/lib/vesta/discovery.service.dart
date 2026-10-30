import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';

/// Vesta: finds the family server for an email address, so people sign in with
/// just their email instead of typing a server URL.
///
/// The endpoint is a build setting. Point it at the local sandbox with
/// `--dart-define=VESTA_DISCOVERY_URL=http://cloud.<ip>.nip.io/api/v1/discover`.
const kVestaDiscoveryUrl = String.fromEnvironment(
  'VESTA_DISCOVERY_URL',
  defaultValue: 'https://cloud.vesta-vault.com/api/v1/discover',
);

enum VestaDiscoveryError { notFound, invalidEmail, unavailable }

class VestaDiscoveryException implements Exception {
  final VestaDiscoveryError error;

  const VestaDiscoveryException(this.error);

  @override
  String toString() => 'VestaDiscoveryException($error)';
}

class VestaDiscoveryService {
  final http.Client Function() _client;
  final Uri _endpoint;

  VestaDiscoveryService(this._client, {String endpoint = kVestaDiscoveryUrl}) : _endpoint = Uri.parse(endpoint);

  /// Returns the family's server URL, or throws [VestaDiscoveryException].
  Future<String> discover(String email) async {
    final uri = _endpoint.replace(queryParameters: {'email': email.trim()});

    final http.Response response;
    try {
      response = await _client().get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const VestaDiscoveryException(VestaDiscoveryError.unavailable);
    }

    switch (response.statusCode) {
      case 200:
        final serverUrl = _parseServerUrl(response.body);
        if (serverUrl == null) {
          throw const VestaDiscoveryException(VestaDiscoveryError.unavailable);
        }
        return serverUrl;
      case 404:
        throw const VestaDiscoveryException(VestaDiscoveryError.notFound);
      case 400:
        throw const VestaDiscoveryException(VestaDiscoveryError.invalidEmail);
      default:
        throw const VestaDiscoveryException(VestaDiscoveryError.unavailable);
    }
  }

  static String? _parseServerUrl(String body) {
    try {
      final json = jsonDecode(body);
      final serverUrl = json is Map ? json['serverUrl'] : null;
      if (serverUrl is! String) {
        return null;
      }
      final uri = Uri.tryParse(serverUrl);
      if (uri == null || !uri.isScheme('https') && !uri.isScheme('http') || uri.host.isEmpty) {
        return null;
      }
      return serverUrl;
    } on FormatException {
      return null;
    }
  }
}

final vestaDiscoveryServiceProvider = Provider((_) => VestaDiscoveryService(() => NetworkRepository.client));
