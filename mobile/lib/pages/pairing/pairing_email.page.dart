import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/pairing/pairing_api.dart';

/// Step 1 of pairing auth: email address. Submitting sends a 6-digit code
/// via request-code.ts -- this call also creates the account on first sight
/// of the address, so there's no separate "sign up" step.
@RoutePage()
class PairingEmailPage extends HookWidget {
  const PairingEmailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final emailController = useTextEditingController();
    final isSubmitting = useState(false);
    final errorText = useState<String?>(null);
    final api = useMemoized(() => PairingApi());

    Future<void> submit() async {
      final email = emailController.text.trim();
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        errorText.value = 'Enter a valid email address';
        return;
      }
      isSubmitting.value = true;
      errorText.value = null;
      final result = await api.requestCode(email);
      isSubmitting.value = false;
      if (!context.mounted) {
        return;
      }
      if (!result.isSuccess) {
        errorText.value = result.error;
        return;
      }
      unawaited(context.pushRoute(PairingCodeRoute(email: email)));
    }

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'What\'s your email?',
                style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'We\'ll send you a code to confirm it\'s you. This becomes your Vesta Vault login too.',
                style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceSecondary),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  labelText: 'Email address',
                  border: const OutlineInputBorder(),
                  errorText: errorText.value,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: isSubmitting.value ? null : submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: isSubmitting.value
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send code'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
