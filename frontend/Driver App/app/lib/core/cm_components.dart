import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'network_quality_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Market CM — branded atoms ported faithfully from the authoritative
/// design source (`central-market-ui-design/project/theme.jsx`).
///
/// These complement the existing rich kit in `app_ui.dart` with the small
/// building blocks the mockups rely on: Pill, Avatar, image placeholder,
/// star rating, product card, branded bottom navigation and screen header.
///
/// Everything pulls from [AppPalette] so the Cameroonian palette stays the
/// single source of truth.

// ─────────────────────────────────────────────────────────────
// Pill — small status/label chip (theme.jsx `Pill`)
// ─────────────────────────────────────────────────────────────
enum CmPillVariant { neutral, success, warn, danger, info, dark, accent }

class CmPill extends StatelessWidget {
  const CmPill({
    super.key,
    required this.label,
    this.variant = CmPillVariant.neutral,
    this.icon,
    this.small = false,
  });

  final String label;
  final CmPillVariant variant;
  final IconData? icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _palette(variant);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: small ? 10 : 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: small ? 10.5 : 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _palette(CmPillVariant v) {
    switch (v) {
      case CmPillVariant.success:
        return (AppPalette.primarySoft, AppPalette.primaryDark);
      case CmPillVariant.warn:
        return (AppPalette.accentSoft, const Color(0xFF8E5A00));
      case CmPillVariant.danger:
        return (AppPalette.secondarySoft, AppPalette.secondary);
      case CmPillVariant.info:
        return (AppPalette.infoSoft, const Color(0xFF3730A3));
      case CmPillVariant.dark:
        return (AppPalette.text, Colors.white);
      case CmPillVariant.accent:
        return (AppPalette.accent, const Color(0xFF1A0F00));
      case CmPillVariant.neutral:
        return (AppPalette.bgSoft, AppPalette.textMuted);
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Avatar — gradient initials (theme.jsx `Avatar`)
// ─────────────────────────────────────────────────────────────
enum CmAvatarVariant { primary, accent, coral, info, dark }

class CmAvatar extends StatelessWidget {
  const CmAvatar({
    super.key,
    required this.name,
    this.size = 36,
    this.variant = CmAvatarVariant.primary,
    this.ring = false,
  });

  final String name;
  final double size;
  final CmAvatarVariant variant;
  final bool ring;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0]).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _gradient(variant);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        shape: BoxShape.circle,
        border: ring
            ? Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: variant == CmAvatarVariant.accent
              ? const Color(0xFF1A0F00)
              : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }

  LinearGradient _gradient(CmAvatarVariant v) {
    const begin = Alignment.topLeft;
    const end = Alignment.bottomRight;
    switch (v) {
      case CmAvatarVariant.accent:
        return const LinearGradient(
            colors: [Color(0xFFFFC940), AppPalette.accentDark],
            begin: begin,
            end: end);
      case CmAvatarVariant.coral:
        return const LinearGradient(
            colors: [Color(0xFFF26B6F), AppPalette.secondary],
            begin: begin,
            end: end);
      case CmAvatarVariant.info:
        return const LinearGradient(
            colors: [Color(0xFF6B8FFF), Color(0xFF2563EB)],
            begin: begin,
            end: end);
      case CmAvatarVariant.dark:
        return const LinearGradient(
            colors: [Color(0xFF4A5A54), AppPalette.text],
            begin: begin,
            end: end);
      case CmAvatarVariant.primary:
        return const LinearGradient(
            colors: [Color(0xFF1A9670), AppPalette.primary],
            begin: begin,
            end: end);
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Image placeholder — soft gradient + watermark icon (theme.jsx `Ph`).
// Renders [imageUrl] when provided, falling back to the gradient tone.
// ─────────────────────────────────────────────────────────────
enum CmTone { primary, accent, cream, coral, sky }

class CmImagePlaceholder extends StatelessWidget {
  const CmImagePlaceholder({
    super.key,
    this.icon = LucideIcons.package,
    this.height = 120,
    this.radius = AppRadii.sm,
    this.tone = CmTone.primary,
    this.label,
    this.imageUrl,
  });

  final IconData icon;
  final double height;
  final double radius;
  final CmTone tone;
  final String? label;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final (gradient, fg) = _tone(tone);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null && imageUrl!.isNotEmpty)
              Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    _fallback(gradient, fg),
              )
            else
              _fallback(gradient, fg),
            if (label != null)
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Text(
                  label!.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(LinearGradient gradient, Color fg) => DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: Center(
          child: Icon(icon,
              size: (height * 0.4).clamp(18, 48).toDouble(),
              color: fg.withValues(alpha: 0.85)),
        ),
      );

  (LinearGradient, Color) _tone(CmTone t) {
    const begin = Alignment.topLeft;
    const end = Alignment.bottomRight;
    switch (t) {
      case CmTone.accent:
        return (
          const LinearGradient(
              colors: [Color(0xFFFEF4D6), Color(0xFFFCE9B0)],
              begin: begin,
              end: end),
          AppPalette.accentDark
        );
      case CmTone.cream:
        return (
          const LinearGradient(
              colors: [Color(0xFFF5F0E0), Color(0xFFEDE5CC)],
              begin: begin,
              end: end),
          AppPalette.textMuted
        );
      case CmTone.coral:
        return (
          const LinearGradient(
              colors: [Color(0xFFFEECEC), Color(0xFFFBD9DA)],
              begin: begin,
              end: end),
          AppPalette.secondary
        );
      case CmTone.sky:
        return (
          const LinearGradient(
              colors: [Color(0xFFE0EAFF), Color(0xFFC7D6FB)],
              begin: begin,
              end: end),
          const Color(0xFF3730A3)
        );
      case CmTone.primary:
        return (
          const LinearGradient(
              colors: [Color(0xFFE6F2EC), Color(0xFFD9EADF)],
              begin: begin,
              end: end),
          AppPalette.primary
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Stars — rating row (theme.jsx `Stars`)
// ─────────────────────────────────────────────────────────────
class CmStars extends StatelessWidget {
  const CmStars({super.key, required this.value, this.size = 12});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final rounded = value.round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = (i + 1) <= rounded;
        return Icon(
          LucideIcons.star,
          size: size,
          color: filled ? AppPalette.accent : AppPalette.bgDeep,
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Branded screen header (theme.jsx `ScreenHeader`)
// ─────────────────────────────────────────────────────────────
class CmScreenHeader extends StatelessWidget {
  const CmScreenHeader({
    super.key,
    this.title,
    this.subtitle,
    this.onBack,
    this.actions,
    this.dark = false,
  });

  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final onColor = dark ? Colors.white : AppPalette.text;
    final onColorSoft =
        dark ? Colors.white.withValues(alpha: 0.7) : AppPalette.textMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          if (onBack != null) ...[
            _HeaderIconBtn(
              icon: LucideIcons.arrowLeft,
              onTap: onBack!,
              dark: dark,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      letterSpacing: -0.2,
                      color: onColor,
                    ),
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: onColorSoft,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  const _HeaderIconBtn({
    required this.icon,
    required this.onTap,
    this.dark = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        side: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.18)
              : AppPalette.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon,
              size: 20, color: dark ? Colors.white : AppPalette.text),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Product card — catalog/featured tile (theme.jsx shop product card)
// ─────────────────────────────────────────────────────────────
class CmProductCard extends StatelessWidget {
  const CmProductCard({
    super.key,
    required this.name,
    required this.supplier,
    required this.price,
    this.currency = 'FCFA',
    this.tone = CmTone.primary,
    this.icon = LucideIcons.package,
    this.imageUrl,
    this.badge,
    this.rating,
    this.salesLabel,
    this.width,
    this.onTap,
    this.onAdd,
    this.onFavorite,
  });

  final String name;
  final String supplier;
  final String price;
  final String currency;
  final CmTone tone;
  final IconData icon;
  final String? imageUrl;
  final String? badge;
  final double? rating;
  final String? salesLabel;
  final double? width;
  final VoidCallback? onTap;
  final VoidCallback? onAdd;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: width,
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppPalette.border),
        boxShadow: AppPalette.shadowSoft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              CmImagePlaceholder(
                icon: icon,
                height: 132,
                radius: 0,
                tone: tone,
                imageUrl: imageUrl,
              ),
              if (badge != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppPalette.secondary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: _RoundIconBtn(
                  icon: LucideIcons.heart,
                  onTap: onFavorite,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.check,
                        size: 11, color: AppPalette.primary),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        supplier,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppPalette.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.text,
                  ),
                ),
                if (rating != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      CmStars(value: rating!, size: 11),
                      if (salesLabel != null) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '· $salesLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10, color: AppPalette.textMuted),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: RichText(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          text: price,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.text,
                          ),
                          children: [
                            TextSpan(
                              text: ' $currency',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppPalette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _SquareIconBtn(icon: LucideIcons.plus, onTap: onAdd),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: card,
      ),
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  const _RoundIconBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 14, color: AppPalette.textMuted),
        ),
      ),
    );
  }
}

class _SquareIconBtn extends StatelessWidget {
  const _SquareIconBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.text,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: const SizedBox(
          width: 30,
          height: 30,
          child: Icon(LucideIcons.plus, size: 15, color: Colors.white),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Branded bottom navigation (theme.jsx `BottomNav`)
// Pill-highlighted active icon + label + optional badge.
// ─────────────────────────────────────────────────────────────
class CmNavItem {
  const CmNavItem({required this.icon, required this.label, this.badge = 0});
  final IconData icon;
  final String label;
  final int badge;
}

class CmBottomNav extends StatelessWidget {
  const CmBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<CmNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppPalette.card,
        border: Border(top: BorderSide(color: AppPalette.borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(child: _buildItem(i, items[i])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(int index, CmNavItem item) {
    final active = index == currentIndex;
    final color = active ? AppPalette.primary : AppPalette.textMuted;
    return InkWell(
      onTap: () => onSelect(index),
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppDurations.instant,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: active ? AppPalette.primarySoft : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(item.icon, size: 22, color: color),
                  if (item.badge > 0)
                    Positioned(
                      top: -4,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: BoxDecoration(
                          color: AppPalette.secondary,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppPalette.card, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          item.badge > 99 ? '99+' : '${item.badge}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/// Helpers responsive partages (web/tablette/desktop). Ajoute par le rollout
/// responsive 2026-06-27 — voir RAPPORT_AMELIORATIONS_20260627.md.
class CmResponsive {
  CmResponsive._();
  static const double phoneMax = 600;
  static const double contentMaxWidth = 720;

  static bool isLargeScreen(BuildContext context) =>
      MediaQuery.of(context).size.width >= phoneMax;

  static Widget center({
    required Widget child,
    double maxWidth = contentMaxWidth,
    AlignmentGeometry alignment = Alignment.topCenter,
  }) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }

  static double dialogWidth(BuildContext context, {double max = 520}) {
    final w = MediaQuery.of(context).size.width;
    return w < max ? w : max;
  }

  /// Enveloppe globale a brancher sur MaterialApp.builder : centre/borne toute
  /// l'app (ecrans, routes, dialogs) sur grand ecran, no-op sur mobile.
  static Widget appWrap(
    BuildContext context,
    Widget? child, {
    double maxWidth = 900,
    Color background = const Color(0xFFE9ECF1),
  }) {
    final content = child ?? const SizedBox.shrink();
    if (MediaQuery.of(context).size.width < phoneMax) return content;
    return ColoredBox(
      color: background,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: content,
        ),
      ),
    );
  }
}

/// Slim banner shown when connectivity drops. Place it at the top of a Scaffold
/// body (above the content) so the driver knows why data may be stale. Collapses
/// to zero height when online, so it costs nothing on the happy path.
class CmOfflineBanner extends StatelessWidget {
  const CmOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<NetworkQuality>(
      stream: NetworkQualityService.instance.qualityStream,
      initialData: NetworkQualityService.instance.current,
      builder: (context, snapshot) {
        final quality = snapshot.data ?? NetworkQuality.online;
        if (quality == NetworkQuality.online) {
          return const SizedBox.shrink();
        }
        final offline = quality == NetworkQuality.offline;
        return Material(
          color: offline ? AppPalette.secondary : Colors.orange.shade700,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    offline ? LucideIcons.wifiOff : LucideIcons.signalLow,
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      offline
                          ? "Hors ligne — les donnees peuvent etre perimees"
                          : "Connexion faible",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
