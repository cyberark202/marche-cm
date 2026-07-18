import '../../core/api_service.dart';

class AdminRepository {
  AdminRepository._();
  static final AdminRepository instance = AdminRepository._();

  final ApiService _api = ApiService();

  String errorMessage(Object e) => _api.toUserMessage(e);

  Future<Map<String, dynamic>> dashboard() =>
      _api.getObject('/api/admin/dashboard/');

  Future<List<Map<String, dynamic>>> users({String query = ''}) {
    final q = query.trim();
    final path = q.isEmpty
        ? '/api/users/'
        : '/api/users/?q=${Uri.encodeQueryComponent(q)}';
    return _api.getList(path);
  }
  Future<List<Map<String, dynamic>>> onlineUsers() =>
      _api.getList('/api/users/online/');
  Future<Map<String, dynamic>> user(int id) =>
      _api.getObject('/api/users/$id/');

  Future<Map<String, dynamic>> suspendUser(int id, {required String reason}) =>
      _api.post('/api/users/$id/suspend/', {'reason': reason});

  Future<Map<String, dynamic>> unsuspendUser(int id) =>
      _api.post('/api/users/$id/unsuspend/', const {});

  Future<Map<String, dynamic>> createManagedUser(
          Map<String, dynamic> payload) =>
      _api.post('/api/users/create_managed_user/', payload);

  Future<List<Map<String, dynamic>>> orders() => _api.getList('/api/orders/');
  Future<List<Map<String, dynamic>>> shipments() =>
      _api.getList('/api/shipments/');

  Future<List<Map<String, dynamic>>> complianceDocuments() =>
      _api.getList('/api/compliance-documents/');
  Future<void> reviewDocument(int id, String status) =>
      _api.post('/api/compliance-documents/$id/review/', {'status': status});

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

  Future<List<Map<String, dynamic>>> escrowHolds() =>
      _api.getList('/api/escrow/holds/');

  Future<void> reconcile({
    required String transactionId,
    required String status,
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

  Future<List<Map<String, dynamic>>> auditEvents() =>
      _api.getList('/api/audit/events/');
  Future<String> exportAuditCsv() =>
      _api.downloadText('/api/admin/audit/export/');

  Future<Map<String, dynamic>> uiConfig() =>
      _api.getObject('/api/ui-config/');
}
