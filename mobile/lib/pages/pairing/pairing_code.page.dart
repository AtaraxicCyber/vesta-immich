import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/pairing/pairing_api.dart';
import 'package:immich_mobile/widgets/forms/pin_input.dart';

/// Step 2 of pairing auth: exchange the emailed 6-digit code for a session
/// token (verify-code.ts), which is the bearer credential the app holds
/// through the rest of the flow for /api/pair/claim.
@RoutePage()
class PairingCodePage extends HookWidget {
  const PairingCodePage({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final isSubmitting = useState(false);
    final errorText = useState<String?>(null);
    final api = useMemoized(() => PairingApi());

    Future<void> submit(String code) async {
      isSubmitting.value = true;
      errorText.value = null;
      final result = await api.verifyCode(email, code);
      isSubmitting.value = false;
      if (!context.mounted) {
        return;
      }
      if (!result.isSuccess || result.value == null) {
        errorText.value = result.error ?? 'Incorrect code';
        return;
      }
      unawaited(context.pushRoute(PairingScanRoute(sessionToken: result.value!)));
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
                'Check your email',
                style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the 6-digit code we sent to $email.',
                style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceSecondary),
              ),
              const SizedBox(height: 32),
              Center(
                child: PinInput(
                  length: 6,
                  autoFocus: true,
                  hasError: errorText.value != null,
                  onCompleted: submit,
                ),
              ),
              if (errorText.value != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: Text(errorText.value!, style: TextStyle(color: context.colorScheme.error)),
                ),
              ],
              const SizedBox(height: 24),
              if (isSubmitting.value) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}
