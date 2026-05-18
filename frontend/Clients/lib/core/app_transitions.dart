import 'package:flutter/material.dart';
import 'app_theme.dart';

enum AppTransitionKind {
  fadeSlide,
  fadeScale,
  slideUp,
  slideRight,
  sharedAxisHorizontal,
  sharedAxisVertical,
  reveal,
}

class AppTransitions {
  static PageRouteBuilder<T> build<T>({
    required Widget Function(BuildContext) builder,
    AppTransitionKind kind = AppTransitionKind.fadeSlide,
    Duration duration = AppDurations.medium,
    Duration reverseDuration = AppDurations.fast,
    bool fullscreenDialog = false,
    bool opaque = true,
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      opaque: opaque,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      pageBuilder: (context, animation, secondary) => builder(context),
      transitionsBuilder: (context, animation, secondary, child) {
        return _buildTransition(kind, animation, secondary, child);
      },
    );
  }

  static Widget _buildTransition(
    AppTransitionKind kind,
    Animation<double> animation,
    Animation<double> secondary,
    Widget child,
  ) {
    switch (kind) {
      case AppTransitionKind.fadeSlide:
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.05, 1.0, curve: Curves.easeOut),
        );
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );

      case AppTransitionKind.fadeScale:
        final scale = Tween<double>(begin: 0.96, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutQuart),
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );

      case AppTransitionKind.slideUp:
        final slide = Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return SlideTransition(position: slide, child: child);

      case AppTransitionKind.slideRight:
        final slide = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return SlideTransition(position: slide, child: child);

      case AppTransitionKind.sharedAxisHorizontal:
        final incoming = Tween<Offset>(
          begin: const Offset(0.15, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        final outgoing = Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.1, 0),
        ).animate(
          CurvedAnimation(parent: secondary, curve: Curves.easeInCubic),
        );
        return SlideTransition(
          position: outgoing,
          child: SlideTransition(
            position: incoming,
            child: FadeTransition(opacity: animation, child: child),
          ),
        );

      case AppTransitionKind.sharedAxisVertical:
        final incoming = Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        final scale = Tween<double>(begin: 0.98, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutQuart),
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: incoming,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );

      case AppTransitionKind.reveal:
        return AnimatedBuilder(
          animation: animation,
          builder: (_, __) {
            return Stack(
              children: [
                Opacity(
                  opacity: animation.value,
                  child: child,
                ),
                IgnorePointer(
                  child: Opacity(
                    opacity: (1 - animation.value).clamp(0.0, 1.0) * 0.4,
                    child: Container(color: Colors.black),
                  ),
                ),
              ],
            );
          },
        );
    }
  }
}

Route<T> appRoute<T>(
  Widget Function(BuildContext) builder, {
  AppTransitionKind kind = AppTransitionKind.fadeSlide,
  bool fullscreenDialog = false,
  RouteSettings? settings,
}) {
  return AppTransitions.build<T>(
    builder: builder,
    kind: kind,
    fullscreenDialog: fullscreenDialog,
    settings: settings,
  );
}

extension NavigatorTransitionExt on NavigatorState {
  Future<T?> pushFade<T>(Widget Function(BuildContext) builder) {
    return push<T>(appRoute<T>(builder, kind: AppTransitionKind.fadeSlide));
  }

  Future<T?> pushSlideUp<T>(Widget Function(BuildContext) builder) {
    return push<T>(appRoute<T>(
      builder,
      kind: AppTransitionKind.slideUp,
      fullscreenDialog: true,
    ));
  }

  Future<T?> pushScale<T>(Widget Function(BuildContext) builder) {
    return push<T>(appRoute<T>(builder, kind: AppTransitionKind.fadeScale));
  }

  Future<T?> pushSharedAxis<T>(Widget Function(BuildContext) builder) {
    return push<T>(
      appRoute<T>(builder, kind: AppTransitionKind.sharedAxisHorizontal),
    );
  }
}

class FadeThrough extends StatelessWidget {
  const FadeThrough({
    super.key,
    required this.child,
    required this.keyValue,
    this.duration = AppDurations.fast,
  });

  final Widget child;
  final Object keyValue;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, anim) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: slide, child: c),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(keyValue),
        child: child,
      ),
    );
  }
}

class StaggeredList extends StatelessWidget {
  const StaggeredList({
    super.key,
    required this.children,
    this.stagger = const Duration(milliseconds: 60),
    this.itemDuration = const Duration(milliseconds: 420),
  });

  final List<Widget> children;
  final Duration stagger;
  final Duration itemDuration;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(children.length, (i) {
        return _StaggeredItem(
          delay: stagger * i,
          duration: itemDuration,
          child: children[i],
        );
      }),
    );
  }
}

class _StaggeredItem extends StatefulWidget {
  const _StaggeredItem({
    required this.child,
    required this.delay,
    required this.duration,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final curved = CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
        ).value;
        return Opacity(
          opacity: curved,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - curved)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.duration = const Duration(milliseconds: 120),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final Duration duration;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    lowerBound: 0,
    upperBound: 1,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.forward(),
      onTapCancel: () => _controller.reverse(),
      onTapUp: (_) {
        _controller.reverse();
      },
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Transform.scale(
          scale: 1 - (_controller.value * (1 - widget.scale)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
