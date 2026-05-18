import 'package:flutter/material.dart';

import '../../core/api_service.dart';

class SensitiveActionVerification {
  const SensitiveActionVerification({
    required this.challengeToken,
    required this.verificationCode,
  });

  final String challengeToken;
  final String verificationCode;
}

class SensitiveActionService {
  SensitiveActionService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  Future<SensitiveActionVerification?> requestAndCollectCode({
    required BuildContext context,
    required String? token,
    required String actionKey,
    required String actionLabel,
  }) async {
    final accessToken = (token ?? "").trim();
    if (accessToken.isEmpty) {
      throw Exception("Session invalide. Reconnectez-vous.");
    }

    var challengeToken = await _requestCode(
      token: accessToken,
      actionKey: actionKey,
    );
    if (!context.mounted) {
      return null;
    }

    final code = await _openCodeDialog(
      context: context,
      actionLabel: actionLabel,
      onResend: () async {
        challengeToken = await _requestCode(
          token: accessToken,
          actionKey: actionKey,
        );
      },
    );
    if (code == null || code.isEmpty) {
      return null;
    }
    return SensitiveActionVerification(
      challengeToken: challengeToken,
      verificationCode: code,
    );
  }

  Future<String> _requestCode({
    required String token,
    required String actionKey,
  }) async {
    final payload = await _api.post(
      "/api/auth/sensitive-action/request/",
      {"action_key": actionKey},
      token: token,
    );
    final challengeToken = (payload["challenge_token"] ?? "").toString().trim();
    if (challengeToken.isEmpty) {
      throw Exception("Echec de generation du code de securite.");
    }
    return challengeToken;
  }

  Future<String?> _openCodeDialog({
    required BuildContext context,
    required String actionLabel,
    required Future<void> Function() onResend,
  }) async {
    final codeController = TextEditingController();
    var busy = false;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text("Verification: $actionLabel"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Un code a 6 chiffres a ete envoye sur votre email.",
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: "Code de securite",
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
                            await onResend();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Nouveau code envoye."),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceFirst("Exception: ", ""),
                                ),
                              ),
                            );
                          } finally {
                            if (context.mounted) {
                              setState(() => busy = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.refresh),
                  label: Text(busy ? "Envoi..." : "Renvoyer code"),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text("Annuler"),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () {
                      final code = codeController.text.trim();
                      if (code.length != 6) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text("Code invalide (6 chiffres)."),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(ctx, code);
                    },
              child: const Text("Valider"),
            ),
          ],
        ),
      ),
    );
    codeController.dispose();
    return result;
  }
}
