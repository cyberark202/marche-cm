import '../../core/api_service.dart';

/// Single gateway to every backend endpoint the admin console consumes.
/// Keeps endpoint strings in one place and gives screens typed-ish helpers.
class AdminRepository {
  AdminRepository._();
  static final AdminRepository instance = AdminRepository._();

  final ApiService _api = ApiService();

  String errorMessage(Object e) => _api.toUserMessage(e);

  // ── Dashboard ────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> dashboard() =>
      _api.getObject('/api/admin/dashboard/');

  // ── Users ─────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> users() => _api.getList('/api/users/');
  Future<List<Map<String, dynamic>>> onlineUsers() =>
      _api.getList('/api/users/online/');
  Future<Map<String, dynamic>> user(int id) =>
      _api.getObject('/api/users/$id/');

  // ── Orders & shipments (aggregates) ────────────────────────────────────────
  Future<List<Map<String, dynamic>>> orders() => _api.getList('/api/orders/');
  Future<List<Map<String, dynamic>>> shipments() =>
      _api.getList('/api/shipments/');

  // ── Compliance / KYC ───────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> complianceDocuments() =>
      _api.getList('/api/compliance-documents/');
  Future<void> reviewDocument(int id, String status) =>
      _api.post('/api/compliance-documents/$id/review/', {'status': status});

  // ── Disputes ────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> shipmentDisputes() =>
      _api.getList('/api/shipment-disputes/');
  Future<Map<String, dynamic>> shipmentDispute(int id) =>
      _api.getObject('/api/shipment-disputes/$id/');
  Future<void> decideDispute(
    int id, {
    required String decision,
    String resolutionNote = 'Décision admin via console',
  }) =>
      _api.post('/api/shipment-disputes/$id/decide/', {
        'status': 'RESOLVED',
        'admin_decision': decision,
        'resolution_note': resolutionNote,
      });

  // ── Wallet / escrow / reconciliation ────────────────────────────────────────
  Future<List<Map<String, dynamic>>> escrowHolds() =>
      _api.getList('/api/escrow/holds/');

  /// Reconcile a single pending transaction. Requires a prior step-up:
  /// [challengeToken] + [verificationCode] from the 2FA email.
  Future<void> reconcile({
    required String transactionId,
    required String status, // SUCCESS | FAILED
    required String challengeToken,
    required String verificationCode,
    String reason = 'Réconciliation manuelle',
  }) =>
      _api.post('/api/wallets/reconcile/', {
        'transaction_id': transactionId,
        'status': status,
        'challenge_token': challengeToken,
        'verification_code': verificationCode,
        'reason': reason,
      });

  // ── Audit ────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> auditEvents() =>
      _api.getList('/api/audit/events/');
  Future<String> exportAuditCsv() =>
      _api.downloadText('/api/admin/audit/export/');

  // ── Platform config ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> uiConfig() =>
      _api.getObject('/api/ui-config/');
}
