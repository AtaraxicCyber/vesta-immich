import 'package:immich_mobile/services/pairing/device_wifi_channel.dart';

/// A unit's claim label QR encodes `vesta-pair://v1?claim=<token>` plus
/// optional `ssid=`/`pass=` overrides for the setup AP, in case per-unit AP
/// credentials are introduced later (today every unit ships the same
/// Vesta_Vault_Setup/VestaSetup pair -- see defaultSetupSsid/Password).
/// Falls back to treating the whole scanned string as a bare claim token,
/// since the bench-staging label generator that produces these doesn't
/// exist yet and the exact format may still shift.
class ClaimLabel {
  const ClaimLabel({required this.claimToken, required this.setupSsid, required this.setupPassword});

  final String claimToken;
  final String setupSsid;
  final String setupPassword;

  static ClaimLabel? tryParse(String scanned) {
    final trimmed = scanned.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == 'vesta-pair') {
      final claim = uri.queryParameters['claim'];
      if (claim == null || claim.isEmpty) {
        return null;
      }
      return ClaimLabel(
        claimToken: claim,
        setupSsid: uri.queryParameters['ssid'] ?? defaultSetupSsid,
        setupPassword: uri.queryParameters['pass'] ?? defaultSetupPassword,
      );
    }

    if (RegExp(r'^[0-9a-fA-F]{16,}$').hasMatch(trimmed)) {
      return ClaimLabel(claimToken: trimmed, setupSsid: defaultSetupSsid, setupPassword: defaultSetupPassword);
    }

    return null;
  }
}
