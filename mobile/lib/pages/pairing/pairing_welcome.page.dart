import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/routing/router.dart';

/// Entry point for app-driven pairing (PHASE1-SETUP-REDESIGN.md). Reached
/// from the login screen's "Set up a new Vesta Vault" link -- this whole
/// flow exists to replace typing a Tailscale key or a captive-portal WiFi
/// form with unbox -> scan -> done.
@RoutePage()
class PairingWelcomePage extends StatelessWidget {
  const PairingWelcomePage({super.key});

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
              Icon(Icons.qr_code_scanner_rounded, size: 96, color: context.primaryColor),
              const SizedBox(height: 24),
              Text(
                'Set up your Vesta Vault',
                textAlign: TextAlign.center,
                style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Plug in your unit, then scan the label on the bottom to connect it to your account and your WiFi.',
                textAlign: TextAlign.center,
                style: context.textTheme.bodyLarge?.copyWith(color: context.colorScheme.onSurfaceSecondary),
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: () => context.pushRoute(const PairingEmailRoute()),
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Get started')),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: () => context.maybePop(), child: const Text('Not now')),
            ],
          ),
        ),
      ),
    );
  }
}
