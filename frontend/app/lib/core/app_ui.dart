import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'app_theme.dart';

/// Animated, gradient-aware page background.
class AppPageBackground extends StatelessWidget {
  const AppPageBackground({
    super.key,
    required this.child,
    this.gradient,
    this.decorated = true,
  });

  final Widget child;
  final LinearGradient? gradient;
  final bool decorated;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: gradient ?? AppPalette.gradientPageLight,
            ),
          ),
        ),
        if (decorated) ...[
          Positioned(
            top: -120,
            right: -80,
            child: _GlowBlob(
              size: 320,
              colors: [
                AppPalette.primary.withValues(alpha: 0.14),
                AppPalette.primary.withValues(alpha: 0.0),
              ],
            ),
          ),
          Positioned(
            top: 180,
            left: -90,
            child: _GlowBlob(
              size: 240,
              colors: [
                AppPalette.secondary.withValues(alpha: 0.10),
                AppPalette.secondary.withValues(alpha: 0.0),
              ],
            ),
          ),
          Positioned(
            bottom: -100,
            right: -60,
            child: _GlowBlob(
              size: 280,
              colors: [
                AppPalette.accent.withValues(alpha: 0.08),
                AppPalette.accent.withValues(alpha: 0.0),
              ],
            ),
          ),
        ],
        Positioned.fill(child: child),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}

/// Modern card with soft shadow, optional gradient, and tap handling.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.gradient,
    this.color,
    this.borderColor,
    this.onTap,
    this.radius = AppRadii.lg,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Gradient? gradient;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double radius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Colors.white) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppPalette.borderSoft),
        boxShadow: elevated ? AppPalette.shadowSoft : null,
      ),
      child: child,
    );
    return Padding(
      padding: margin,
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(radius),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius),
                splashColor: AppPalette.primary.withValues(alpha: 0.07),
                highlightColor: AppPalette.primary.withValues(alpha: 0.04),
                child: content,
              ),
            ),
    );
  }
}

/// Glassmorphic card using backdrop blur.
class AppGlassCard extends StatelessWidget {
  const AppGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadii.lg,
    this.tint,
    this.blur = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (tint ?? Colors.white).withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.7),
              width: 1.2,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class AppHeaderPanel extends StatelessWidget {
  const AppHeaderPanel({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.icon,
    this.gradient,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final isGradient = gradient != null;
    final onColor = isGradient ? Colors.white : AppPalette.text;
    final onColorSoft = isGradient
        ? Colors.white.withValues(alpha: 0.86)
        : AppPalette.textMuted;
    return AppSectionCard(
      padding: const EdgeInsets.all(18),
      gradient: gradient,
      borderColor: isGradient ? Colors.transparent : null,
      elevated: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isGradient
                    ? Colors.white.withValues(alpha: 0.18)
                    : AppPalette.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(
                  color: isGradient
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.transparent,
                ),
              ),
              child: Icon(
                icon,
                color: isGradient ? Colors.white : AppPalette.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: onColor,
                        fontSize: 16.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: onColorSoft,
                        fontSize: 13,
                        height: 1.3,
                      ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class AppMetricTile extends StatelessWidget {
  const AppMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tint = AppPalette.primary,
    this.trend,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final String? trend;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 30 : 38,
                height: compact ? 30 : 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      tint.withValues(alpha: 0.22),
                      tint.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(icon, color: tint, size: compact ? 16 : 20),
              ),
              const Spacer(),
              if (trend != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppPalette.success.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        AppIcons.trending,
                        size: 12,
                        color: AppPalette.success,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        trend!,
                        style: const TextStyle(
                          color: AppPalette.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            value,
            style: TextStyle(
              color: AppPalette.text,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 16 : 20,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppPalette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    super.key,
    required this.text,
    required this.color,
    this.icon,
    this.filled = false,
  });

  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: filled ? color : color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: filled ? Colors.white : color,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip with optional leading icon and gradient background when active.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: AnimatedContainer(
          duration: AppDurations.fast,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected ? AppPalette.gradientPrimary : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected ? Colors.transparent : AppPalette.border,
            ),
            boxShadow: selected ? AppPalette.shadowStrong : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: selected ? Colors.white : AppPalette.textMuted,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppPalette.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hero section with gradient background used on dashboards.
class AppHeroBanner extends StatelessWidget {
  const AppHeroBanner({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    this.gradient,
    this.icon,
  });

  final String title;
  final String subtitle;
  final Widget? action;
  final Gradient? gradient;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: gradient ?? AppPalette.gradientPrimary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppPalette.shadowStrong,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            right: 20,
            bottom: -30,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 8), action!],
            ],
          ),
        ],
      ),
    );
  }
}

/// Row of section header with optional trailing action.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppPalette.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppPalette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppPalette.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Icon badge with optional red dot.
class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    super.key,
    required this.icon,
    this.onTap,
    this.count = 0,
    this.showDot = false,
    this.tint = AppPalette.text,
    this.bgColor,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final int count;
  final bool showDot;
  final Color tint;
  final Color? bgColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: bgColor ?? Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppPalette.borderSoft),
                boxShadow: AppPalette.shadowSoft,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 19, color: tint),
            ),
            if (count > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    gradient: AppPalette.gradientAccent,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    count > 99 ? "99+" : "$count",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              )
            else if (showDot)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AppPalette.accentWarm,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Gradient action button — primary CTA.
class AppGradientButton extends StatelessWidget {
  const AppGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.gradient,
    this.loading = false,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Gradient? gradient;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    return Opacity(
      opacity: disabled ? 0.7 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              gradient: gradient ?? AppPalette.gradientPrimary,
              borderRadius: BorderRadius.circular(AppRadii.md),
              boxShadow: AppPalette.shadowStrong,
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 19),
                          const SizedBox(width: 9),
                        ],
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty-state placeholder with icon and call-to-action.
class AppEmptyStateView extends StatelessWidget {
  const AppEmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

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
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppPalette.primary.withValues(alpha: 0.12),
                    AppPalette.primary.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: AppPalette.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppPalette.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppPalette.textMuted,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton loading widgets (no external packages needed)
// ---------------------------------------------------------------------------

/// Animated pulsing placeholder box — use to build skeleton layouts.
class AppSkeletonBox extends StatefulWidget {
  const AppSkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<AppSkeletonBox> createState() => _AppSkeletonBoxState();
}

class _AppSkeletonBoxState extends State<AppSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            Colors.grey.shade200,
            Colors.grey.shade300,
            _anim.value,
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A skeleton row that mimics a ListTile with a leading avatar.
class AppSkeletonTile extends StatelessWidget {
  const AppSkeletonTile({super.key, this.hasSubtitle = true});
  final bool hasSubtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const AppSkeletonBox(width: 42, height: 42, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSkeletonBox(height: 13),
                if (hasSubtitle) ...[
                  const SizedBox(height: 6),
                  const AppSkeletonBox(width: 160, height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A skeleton that fills a card shape — use for card-based list screens.
class AppSkeletonCard extends StatelessWidget {
  const AppSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const AppSkeletonBox(width: 44, height: 44, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSkeletonBox(height: 13),
                  const SizedBox(height: 7),
                  const AppSkeletonBox(width: 180, height: 11),
                  const SizedBox(height: 5),
                  const AppSkeletonBox(width: 100, height: 10),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const AppSkeletonBox(width: 48, height: 22, radius: 12),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for a full list screen: shows [count] skeleton cards.
class AppSkeletonListView extends StatelessWidget {
  const AppSkeletonListView({super.key, this.count = 5});
  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: count,
      itemBuilder: (_, __) => const AppSkeletonCard(),
    );
  }
}

/// Skeleton for a KPI / metric card row — 2 side-by-side boxes.
class AppSkeletonMetricRow extends StatelessWidget {
  const AppSkeletonMetricRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(child: _metricBox()),
          const SizedBox(width: 10),
          Expanded(child: _metricBox()),
        ],
      ),
    );
  }

  Widget _metricBox() => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeletonBox(width: 60, height: 10),
              SizedBox(height: 8),
              AppSkeletonBox(width: 80, height: 22, radius: 6),
              SizedBox(height: 6),
              AppSkeletonBox(width: 100, height: 10),
            ],
          ),
        ),
      );
}
