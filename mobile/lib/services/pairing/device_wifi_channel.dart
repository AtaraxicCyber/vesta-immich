import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Default setup-AP credentials baked into every unit's image by
/// 2_configure-network.sh (hostapd.conf: ssid=Vesta_Vault_Setup,
/// wpa_passphrase=VestaSetup). Static today -- if per-unit AP credentials
/// are ever introduced, the claim-label QR payload carries an override and
/// these become the fallback rather than the only option.
const String defaultSetupSsid = 'Vesta_Vault_Setup';
const String defaultSetupPassword = 'VestaSetup';

/// Wraps the native vesta.pairing/wifi MethodChannel: joins a Vesta unit's
/// temporary setup AP (WifiNetworkSpecifier, API 29+, no location permission
/// needed) and relays the WiFi-handoff POST to it. See
/// VestaWifiPairingPlugin.kt for why this can't just be a normal http.post --
/// the setup AP has no internet, so the request has to be bound to that
/// specific network rather than the phone's default route.
class DeviceWifiChannel {
  static const _channel = MethodChannel('vesta.pairing/wifi');
  final _log = Logger('DeviceWifiChannel');

  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (e) {
      _log.warning('isSupported check failed', e);
      return false;
    }
  }

  /// Joins the unit's setup AP. Returns true once the phone has an active
  /// (internet-less) link-layer connection to it.
  Future<DeviceWifiResult<void>> joinSetupNetwork({
    String ssid = defaultSetupSsid,
    String password = defaultSetupPassword,
  }) async {
    try {
      await _channel.invokeMethod('joinSetupNetwork', {'ssid': ssid, 'password': password});
      return const DeviceWifiResult.success(null);
    } on PlatformException catch (e) {
      _log.warning('joinSetupNetwork(${e.code}) failed', e);
      return DeviceWifiResult.failure(_describe(e));
    }
  }

  /// POSTs the customer's home WiFi SSID/password to the unit's local
  /// /api/local-pair endpoint over the just-joined setup AP. Blocks for up to
  /// ~30s on the device side while it actually associates -- see
  /// setup_portal.py's local_pair() for why this is truthful rather than
  /// optimistic.
  Future<DeviceWifiResult<bool>> handOffWifiCredentials({required String ssid, required String password}) async {
    try {
      final raw = await _channel.invokeMethod<Map>('postJson', {
        'path': '/api/local-pair',
        'body': jsonEncode({'ssid': ssid, 'password': password}),
      });
      final status = raw?['status'] as int?;
      final bodyStr = raw?['body'] as String?;
      if (status == null || bodyStr == null) {
        return const DeviceWifiResult.failure('No response from the unit');
      }
      final body = bodyStr.isEmpty ? <String, dynamic>{} : jsonDecode(bodyStr) as Map<String, dynamic>;
      if (status != 200 || body['ok'] != true) {
        final error = body['error'] as String? ?? 'association_failed';
        return DeviceWifiResult.failure(_describeLocalPairError(error));
      }
      return const DeviceWifiResult.success(true);
    } on PlatformException catch (e) {
      _log.warning('handOffWifiCredentials(${e.code}) failed', e);
      return DeviceWifiResult.failure(_describe(e));
    }
  }

  Future<void> releaseSetupNetwork() async {
    try {
      await _channel.invokeMethod('releaseSetupNetwork');
    } catch (e) {
      _log.warning('releaseSetupNetwork failed', e);
    }
  }

  String _describe(PlatformException e) {
    switch (e.code) {
      case 'unsupported':
        return 'This phone\'s Android version is too old for automatic WiFi handoff.';
      case 'timeout':
      case 'unavailable':
        return 'Could not connect to the unit. Make sure it\'s powered on and nearby.';
      default:
        return e.message ?? 'Could not connect to the unit.';
    }
  }

  String _describeLocalPairError(String error) {
    switch (error) {
      case 'association_failed':
        return 'The unit couldn\'t join that WiFi network. Double check the password.';
      case 'locked':
        return 'This unit is locked. Contact support.';
      default:
        return error;
    }
  }
}

class DeviceWifiResult<T> {
  const DeviceWifiResult.success(this.value) : error = null;
  const DeviceWifiResult.failure(this.error) : value = null;

  final T? value;
  final String? error;

  bool get isSuccess => error == null;
}
