import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/driver_dio_client.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SensitiveActionVerification {
  const SensitiveActionVerification({
    required this.challengeToken,
    required this.verificationCode,
  });

  final String challengeToken;
  final String verificationCode;
}

Future<SensitiveActionVerification?> collectSensitiveActionCode(
  BuildContext context, {
  required String actionKey,
  required String actionLabel,
}) async {
  Future<String> requestChallenge() async {
    final res = await DriverDioClient.dio.post(
      '/api/auth/sensitive-action/request/',
      data: {'action_key': actionKey},
    );
    final token = (res.data['challenge_token'] ?? '').toString().trim();
    if (token.isEmpty) {
      throw Exception('Échec de génération du code de sécurité.');
    }
    return token;
  }

  String challengeToken;
  try {
    challengeToken = await requestChallenge();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiError.friendly(e))),
      );
    }
    return null;
  }
  if (!context.mounted) return null;

  final controller = TextEditingController();
  bool busy = false;
  final code = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Vérification : $actionLabel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Un code à 6 chiffres a été envoyé sur votre email.'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Code de sécurité',
                counterText: '',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          challengeToken = await requestChallenge();
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text('Nouveau code envoyé.')),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(ApiError.friendly(e))),
                            );
                          }
                        } finally {
                          if (ctx.mounted) setState(() => busy = false);
                        }
                      },
                icon: const Icon(LucideIcons.refreshCw),
                label: Text(busy ? 'Envoi...' : 'Renvoyer le code'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () {
                    final value = controller.text.trim();
                    if (value.length != 6) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content: Text('Code invalide (6 chiffres).')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, value);
                  },
            child: const Text('Valider'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  if (code == null || code.isEmpty) return null;
  return SensitiveActionVerification(
    challengeToken: challengeToken,
    verificationCode: code,
  );
}
