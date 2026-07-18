class Fmt {
  const Fmt._();

  static String thousands(num value) {
    final isNeg = value < 0;
    final digits = value.abs().round().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return isNeg ? '-${buffer.toString()}' : buffer.toString();
  }

  static String fcfa(num value) => '${thousands(value)} FCFA';

  static String compact(num value) {
    final v = value.abs();
    String body;
    String suffix;
    if (v >= 1000000000) {
      body = (value / 1000000000).toStringAsFixed(1);
      suffix = ' Md';
    } else if (v >= 1000000) {
      body = (value / 1000000).toStringAsFixed(1);
      suffix = ' M';
    } else if (v >= 1000) {
      body = (value / 1000).toStringAsFixed(1);
      suffix = ' k';
    } else {
      return thousands(value);
    }
    body = body.replaceAll('.', ',');
    if (body.endsWith(',0')) body = body.substring(0, body.length - 2);
    return '$body$suffix';
  }

  static String compactFcfa(num value) => '${compact(value)} FCFA';

  static num amount(dynamic raw) {
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw.replaceAll(' ', '')) ?? 0;
    return 0;
  }

  static String relative(dynamic isoRaw) {
    final iso = (isoRaw ?? '').toString();
    if (iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 60) return "à l'instant";
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
    if (diff.inDays < 30) return 'il y a ${(diff.inDays / 7).floor()} sem';
    return 'il y a ${(diff.inDays / 30).floor()} mois';
  }

  static String dateTime(dynamic isoRaw) {
    final iso = (isoRaw ?? '').toString();
    if (iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final l = dt.toLocal();
    const months = [
      'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
      'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
    ];
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.day} ${months[l.month - 1]} · $hh:$mm';
  }

  static String initials(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
