import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/routing/router.dart';

/// Step 5: the app's job is done. The unit itself now polls
/// /api/pair/confirm with its own passkey until Cloudflare reports the
/// claim, then provisions its local Immich admin user -- that can take up
/// to PAIRING_POLL_INTERVAL_SECONDS (10s) plus however long the WiFi
/// association took, so this screen doesn't promise the vault is reachable
/// yet, just that pairing was accepted.
///
/// There's no /api/pair/status endpoint yet for the app to poll for
/// completion (PHASE1-SETUP-REDESIGN.md step 8's "app polls Cloudflare"),
/// so this is a static confirmation rather than a live status screen.
@RoutePage()
class PairingSuccessPage extends StatelessWidget {
  const PairingSuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.check_circle_rounded, size: 96, color: context.colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                'You\'re all set',
                textAlign: TextAlign.center,
                style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Your Vesta Vault is finishing setup and will be ready in a minute or two. '
                'Log in with the same email once it\'s online.',
                textAlign: TextAlign.center,
                style: context.textTheme.bodyLarge?.copyWith(color: context.colorScheme.onSurfaceSecondary),
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: () => context.replaceRoute(const LoginRoute()),
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Done')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
