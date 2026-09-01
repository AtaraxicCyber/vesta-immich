import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/pairing/device_wifi_channel.dart';

enum _Stage { form, joiningSetupAp, handingOff, done, error }

/// Step 4: the actual WiFi handoff this whole flow exists to replace a
/// captive portal with. Joins the unit's temporary setup AP (invisible to
/// the customer -- no browser, no WiFi-picker detour) and relays the home
/// network's credentials to it over that link.
///
/// If the unit is already online via Ethernet, the customer skips this
/// screen entirely -- there is nothing for the app to hand off.
@RoutePage()
class PairingWifiPage extends HookWidget {
  const PairingWifiPage({super.key, required this.setupSsid, required this.setupPassword});

  final String setupSsid;
  final String setupPassword;

  @override
  Widget build(BuildContext context) {
    final ssidController = useTextEditingController();
    final passwordController = useTextEditingController();
    final stage = useState(_Stage.form);
    final errorText = useState<String?>(null);
    final channel = useMemoized(() => DeviceWifiChannel());
    useEffect(() => () => unawaited(channel.releaseSetupNetwork()), [channel]);

    Future<void> submit() async {
      final homeSsid = ssidController.text.trim();
      final homePassword = passwordController.text;
      if (homeSsid.isEmpty) {
        errorText.value = 'Enter your WiFi network name';
        return;
      }

      errorText.value = null;

      if (!await channel.isSupported()) {
        errorText.value =
            'Your phone can\'t connect automatically. Join "$setupSsid" manually in WiFi settings, '
            'then come back to this screen.';
        stage.value = _Stage.error;
        return;
      }

      stage.value = _Stage.joiningSetupAp;
      final joinResult = await channel.joinSetupNetwork(ssid: setupSsid, password: setupPassword);
      if (!context.mounted) {
        return;
      }
      if (!joinResult.isSuccess) {
        errorText.value = joinResult.error;
        stage.value = _Stage.error;
        return;
      }

      stage.value = _Stage.handingOff;
      final handoffResult = await channel.handOffWifiCredentials(ssid: homeSsid, password: homePassword);
      await channel.releaseSetupNetwork();
      if (!context.mounted) {
        return;
      }
      if (!handoffResult.isSuccess) {
        errorText.value = handoffResult.error;
        stage.value = _Stage.error;
        return;
      }

      stage.value = _Stage.done;
      unawaited(context.pushRoute(const PairingSuccessRoute()));
    }

    final isBusy = stage.value == _Stage.joiningSetupAp || stage.value == _Stage.handingOff;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Connect to WiFi', style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Enter your home WiFi network. Your Vesta Vault will join it automatically -- '
                'no need to connect to it yourself.',
                style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceSecondary),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: ssidController,
                enabled: !isBusy,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Network name (SSID)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                enabled: !isBusy,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              ),
              if (errorText.value != null) ...[
                const SizedBox(height: 12),
                Text(errorText.value!, style: TextStyle(color: context.colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: isBusy ? null : submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: isBusy
                      ? Text(stage.value == _Stage.joiningSetupAp ? 'Connecting to unit...' : 'Sending WiFi...')
                      : const Text('Connect'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: isBusy ? null : () => context.pushRoute(const PairingSuccessRoute()),
                child: const Text('My unit is already on Ethernet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
