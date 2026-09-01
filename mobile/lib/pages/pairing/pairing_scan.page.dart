import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/pairing/claim_label.dart';
import 'package:immich_mobile/services/pairing/pairing_api.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Step 3: scan the claim label printed on the unit at bench-staging time.
/// A hit calls /api/pair/claim with the app's session token -- this only
/// expresses intent to pair; the device itself confirms it once the WiFi
/// handoff (next step) actually lands it online.
@RoutePage()
class PairingScanPage extends HookWidget {
  const PairingScanPage({super.key, required this.sessionToken});

  final String sessionToken;

  @override
  Widget build(BuildContext context) {
    final controller = useMemoized(() => MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates));
    useEffect(() => controller.dispose, [controller]);

    final isProcessing = useState(false);
    final errorText = useState<String?>(null);
    final api = useMemoized(() => PairingApi());

    Future<void> onDetect(BarcodeCapture capture) async {
      if (isProcessing.value) {
        return;
      }
      final raw = capture.barcodes.firstOrNull?.rawValue;
      if (raw == null) {
        return;
      }

      final label = ClaimLabel.tryParse(raw);
      if (label == null) {
        errorText.value = 'That doesn\'t look like a Vesta Vault label. Try again.';
        return;
      }

      isProcessing.value = true;
      errorText.value = null;
      unawaited(controller.stop());

      final result = await api.claim(sessionToken: sessionToken, claimToken: label.claimToken);
      if (!context.mounted) {
        return;
      }

      if (!result.isSuccess) {
        isProcessing.value = false;
        errorText.value = result.error;
        unawaited(controller.start());
        return;
      }

      unawaited(
        context.pushRoute(
          PairingWifiRoute(setupSsid: label.setupSsid, setupPassword: label.setupPassword),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan your unit\'s label')),
      body: Stack(
        children: [
          MobileScanner(controller: controller, onDetect: onDetect),
          if (isProcessing.value) const Center(child: CircularProgressIndicator()),
          if (errorText.value != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Material(
                color: context.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(errorText.value!, style: TextStyle(color: context.colorScheme.onErrorContainer)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
