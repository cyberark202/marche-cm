import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

/// Avis acheteurs — driver reviews (PDF 30).
final _reviewsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await DriverDioClient.dio.get("/api/driver/reviews/");
  final data = res.data;
  if (data is Map) return data.cast<String, dynamic>();
  if (data is List) {
    return {"reviews": data, "average": 0, "count": data.length};
  }
  return const {};
});

class ReviewsPage extends ConsumerWidget {
  const ReviewsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(_reviewsProvider);
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onBack: () => context.canPop() ? context.pop() : null),
            Expanded(
              child: reviewsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: T.primary)),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined,
                          size: 48, color: T.ink4),
                      const SizedBox(height: 12),
                      const Text("Erreur de chargement",
                          style: TextStyle(color: T.ink3, fontSize: 14)),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => ref.invalidate(_reviewsProvider),
                        child: const Text("Réessayer"),
                      ),
                    ],
                  ),
                ),
                data: (data) {
                  final avg = double.tryParse(
                          "${data["average_rating"] ?? data["average"] ?? 0}") ??
                      0;
                  final count = int.tryParse(
                          "${data["reviews_count"] ?? data["count"] ?? 0}") ??
                      0;
                  final dist = (data["distribution"] is Map)
                      ? Map<String, int>.from((data["distribution"] as Map)
                          .map((k, v) => MapEntry("$k",
                              int.tryParse("$v") ?? 0)))
                      : <String, int>{};
                  final tags = ((data["tags"] as List?) ?? const [])
                      .whereType<Map>()
                      .map((e) => e.cast<String, dynamic>())
                      .toList();
                  final reviews = ((data["reviews"] as List?) ?? const [])
                      .whereType<Map>()
                      .map((e) => e.cast<String, dynamic>())
                      .toList();

                  return RefreshIndicator(
                    color: T.primary,
                    onRefresh: () => ref.refresh(_reviewsProvider.future),
                    child: ListView(
                      padding:
                          const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        _RatingSummary(
                            average: avg, count: count, distribution: dist),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _TagsRow(tags: tags),
                        ],
                        const SizedBox(height: 18),
                        if (reviews.isEmpty)
                          const _Empty()
                        else
                          ...reviews.map((r) => _ReviewCard(review: r)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 18),
      decoration: const BoxDecoration(
        gradient: T.gradientDriverHeader,
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(T.rXl),
            bottomRight: Radius.circular(T.rXl)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white))
          else
            const SizedBox(width: 16),
          const Expanded(
            child: Text("Mes avis",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3)),
          ),
        ],
      ),
    );
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({
    required this.average,
    required this.count,
    required this.distribution,
  });
  final double average;
  final int count;
  final Map<String, int> distribution;

  int _pct(String key) {
    if (count == 0) return 0;
    final v = distribution[key] ?? 0;
    return ((v / count) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.line),
        boxShadow: T.shadowSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                average > 0 ? average.toStringAsFixed(1) : "—",
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: T.primaryDeep,
                  letterSpacing: -2.0,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: List.generate(5, (i) {
                  final filled = i < average.round();
                  return Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 14,
                    color: filled ? T.accent : T.ink4,
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text("$count avis",
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: T.ink3)),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                for (final star in ["5", "4", "3", "2", "1"])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          child: Text(star,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: T.ink2)),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: T.surface2,
                                  borderRadius:
                                      BorderRadius.circular(T.rFull),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: (_pct(star) / 100).clamp(0, 1),
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    gradient: T.gradientDriver,
                                    borderRadius:
                                        BorderRadius.circular(T.rFull),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text("${_pct(star)} %",
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: T.ink3)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagsRow extends StatelessWidget {
  const _TagsRow({required this.tags});
  final List<Map<String, dynamic>> tags;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags.take(6))
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: T.primarySoft,
              borderRadius: BorderRadius.circular(T.rFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("${tag["label"] ?? ""}",
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: T.primaryDark)),
                if (tag["count"] != null) ...[
                  const SizedBox(width: 5),
                  Text("${tag["count"]}",
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: T.primary)),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final name = (review["buyer_name"] ?? review["author"] ?? "Anonyme")
        .toString();
    final city = (review["city"] ?? "").toString();
    final comment = (review["comment"] ?? "").toString();
    final rating = int.tryParse("${review["rating"] ?? 0}") ?? 0;
    final dateRaw = (review["created_at"] ?? "").toString();
    final dt = DateTime.tryParse(dateRaw);
    final ago = dt == null
        ? ""
        : (() {
            final diff = DateTime.now().difference(dt);
            if (diff.inDays > 7) return "il y a ${(diff.inDays / 7).floor()} sem";
            if (diff.inDays > 0) return "il y a ${diff.inDays} j";
            if (diff.inHours > 0) return "il y a ${diff.inHours} h";
            return "à l'instant";
          })();
    final tags = ((review["tags"] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();

    final initials = () {
      final src = name.trim();
      if (src.isEmpty) return "·";
      final parts = src.split(RegExp(r"\s+"));
      if (parts.length == 1) {
        return parts.first
            .substring(0, parts.first.length.clamp(0, 2))
            .toUpperCase();
      }
      return (parts[0].isNotEmpty ? parts[0][0] : "") +
          (parts[1].isNotEmpty ? parts[1][0] : "");
    }();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.line),
        boxShadow: T.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: T.gradientPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(initials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: T.ink)),
                    Text("${city.isNotEmpty ? "$city · " : ""}$ago",
                        style: const TextStyle(
                            fontSize: 11,
                            color: T.ink3,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                      i < rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: T.accent,
                      size: 13);
                }),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(comment,
                style: const TextStyle(
                    fontSize: 13,
                    color: T.ink2,
                    height: 1.5,
                    fontWeight: FontWeight.w500)),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final t in tags.take(4))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: T.surface2,
                      borderRadius: BorderRadius.circular(T.rFull),
                    ),
                    child: Text(t,
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: T.ink2)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: T.accentSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star_outline_rounded,
                  size: 36, color: T.accent),
            ),
            const SizedBox(height: 12),
            const Text("Pas encore d'avis",
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: T.ink)),
            const SizedBox(height: 4),
            const Text(
              "Les évaluations de vos acheteurs apparaîtront ici.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: T.ink3),
            ),
          ],
        ),
      ),
    );
  }
}
