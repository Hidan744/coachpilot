// Движение интерфейса: переходы между экранами, появление карточек, счётчики.

import 'package:flutter/material.dart';

/// Переход между экранами: новый экран проявляется и мягко поднимается, старый слегка уходит назад.
class FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeSlidePageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final inCurve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final outCurve = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: inCurve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(inCurve),
        child: ScaleTransition(
          scale: Tween(begin: 1.0, end: 0.96).animate(outCurve),
          child: FadeTransition(opacity: Tween(begin: 1.0, end: 0.6).animate(outCurve), child: child),
        ),
      ),
    );
  }
}

/// Карточка появляется с задержкой по порядку: экран «собирается» сверху вниз.
class Appear extends StatefulWidget {
  const Appear({super.key, required this.child, this.index = 0, this.offset = 24});

  final Widget child;
  final int index;
  final double offset;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Duration(milliseconds: 420 + 60 * widget.index.clamp(0, 10)));
  late final _a = CurvedAnimation(
    parent: _c,
    curve: Interval((60 * widget.index.clamp(0, 10)) / (420 + 60 * widget.index.clamp(0, 10)), 1, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (context, child) => Opacity(
          opacity: _a.value,
          child: Transform.translate(offset: Offset(0, widget.offset * (1 - _a.value)), child: child),
        ),
        child: widget.child,
      );
}

/// Плавный рост значения 0 → 1 при первом показе (для графиков).
class GrowIn extends StatelessWidget {
  const GrowIn({super.key, required this.builder, this.duration = const Duration(milliseconds: 900)});

  final Widget Function(BuildContext context, double t) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => builder(context, t),
      );
}

/// Число, которое «добегает» до значения: «91%», «784», «+12». Нечисловой текст показывается как есть.
class CountUp extends StatelessWidget {
  const CountUp(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  static final _re = RegExp(r'^([+−-]?)(\d+)(.*)$');

  @override
  Widget build(BuildContext context) {
    final m = _re.firstMatch(text);
    if (m == null) return Text(text, style: style);
    final target = int.parse(m[2]!);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${m[1]}${v.round()}${m[3]}', style: style),
    );
  }
}
