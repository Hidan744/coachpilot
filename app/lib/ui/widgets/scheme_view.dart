import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/scheme_animation.dart';
import '../../data/models.dart';

/// Пропорции площадки (ширина / высота) для каждого типа поля.
double fieldAspect(String field) => switch (field) {
      'full' => 1.5,
      'full_v' => 0.68,
      'half' => 1.25,
      'third' => 1.25,
      'box' => 1.6,
      _ => 1.2,
    };

const fieldLabels = {
  'full': 'Всё поле',
  'full_v': 'Поле (вертикально)',
  'half': 'Половина',
  'third': 'Треть',
  'box': 'Штрафная',
  'grid': 'Площадка',
};

const schemeItemLabels = {
  'player_a': 'Игрок (красные)',
  'player_b': 'Игрок (белые)',
  'neutral': 'Нейтральный',
  'goalkeeper': 'Вратарь',
  'cone': 'Конус',
  'ball': 'Мяч',
  'goal': 'Ворота',
  'mini_goal': 'Мини-ворота',
  'pole': 'Стойка',
  'arrow_pass': 'Пас',
  'arrow_run': 'Бег без мяча',
  'arrow_dribble': 'Ведение',
  'zone': 'Зона',
  'label': 'Подпись',
  'pen': 'Линия от руки',
};

class SchemeColors {
  static const grass = Color(0xFF2E7D32);
  static const grassLight = Color(0xFF388E3C);
  static const line = Color(0xE6FFFFFF);
  // Команды на схемах — в цветах клуба: красные и белые.
  static const teamA = Color(0xFFE30613);
  static const teamB = Color(0xFFF2F2F2);
  static const neutral = Color(0xFFFBC02D);
  static const keeper = Color(0xFF212121);
  static const cone = Color(0xFFFF6D00);
  static const pole = Color(0xFFFFEB3B);
}

/// Схема упражнения для просмотра. Если на схеме есть стрелки движения, её можно проиграть:
/// игроки и мяч двигаются по стрелкам шаг за шагом.
class SchemeView extends StatefulWidget {
  const SchemeView(this.scheme, {super.key, this.selected});

  final Scheme scheme;
  final int? selected;

  @override
  State<SchemeView> createState() => _SchemeViewState();
}

class _SchemeViewState extends State<SchemeView> with SingleTickerProviderStateMixin {
  late SchemeAnimation _anim = SchemeAnimation(widget.scheme);
  late final AnimationController _c = AnimationController(vsync: this)..addListener(() => setState(() {}));

  /// Секунд на один шаг.
  static const stepSeconds = 1.6;

  @override
  void didUpdateWidget(SchemeView old) {
    super.didUpdateWidget(old);
    // Экран пересоздаёт схему при каждом обновлении данных — сравниваем содержимое, иначе анимация сбрасывалась бы.
    if (!identical(old.scheme, widget.scheme) && jsonEncode(old.scheme.toJson()) != jsonEncode(widget.scheme.toJson())) {
      _anim = SchemeAnimation(widget.scheme);
      _c.reset();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_c.isAnimating) {
      _c.stop();
    } else {
      if (_c.value >= 1) _c.value = 0;
      _c.duration = Duration(milliseconds: (stepSeconds * 1000 * _anim.stepCount).round());
      _c.forward();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final playing = _c.isAnimating;
    final started = _c.value > 0;
    final t = _c.value * _anim.stepCount;
    final canPlay = _anim.hasMotion;
    return AspectRatio(
      aspectRatio: fieldAspect(widget.scheme.field),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          CustomPaint(
            painter: SchemePainter(
              widget.scheme,
              selected: widget.selected,
              positions: started ? _anim.positionsAt(t) : null,
              activeStep: started && _c.value < 1 ? _anim.steps[_anim.stepIndexAt(t)] : null,
              resolved: _anim.resolvedPaths,
            ),
          ),
          if (canPlay && _anim.stepCount > 1 && started)
            Positioned(
              left: 8,
              top: 8,
              child: _Badge('Шаг ${_anim.stepIndexAt(t) + 1} из ${_anim.stepCount}'),
            ),
          if (canPlay)
            Positioned(
              right: 8,
              bottom: 8,
              child: IconButton.filled(
                tooltip: playing ? 'Пауза анимации' : 'Показать движение',
                style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.65)),
                onPressed: _toggle,
                icon: Icon(
                  playing ? Icons.pause : (_c.value >= 1 ? Icons.replay : Icons.play_arrow),
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      );
}

class SchemePainter extends CustomPainter {
  SchemePainter(
    this.scheme, {
    this.selected,
    this.preview,
    this.positions,
    this.activeStep,
    this.showSteps = true,
    this.resolved,
    this.ghosts,
    this.highlightSet,
  });

  final Scheme scheme;
  final int? selected;

  /// Стрелка, которую пользователь тянет прямо сейчас.
  final SchemeItem? preview;

  /// Позиции объектов во время анимации (индекс элемента → точка); отрицательные ключи — появившиеся мячи.
  final Map<int, Offset>? positions;

  /// Шаг, который сейчас проигрывается: остальные стрелки приглушены.
  final int? activeStep;

  /// Подписывать номера шагов у стрелок, если шагов больше одного.
  final bool showSteps;

  /// Пути стрелок с учётом того, где игрок стоит к своему шагу (из SchemeAnimation). Без них — как нарисованы.
  final Map<int, List<Offset>>? resolved;

  /// Полупрозрачные фишки там, где игроки окажутся после всех шагов (редактор).
  final Map<int, Offset>? ghosts;

  /// Подсветка нескольких элементов (например, кому можно отдать пас).
  final Set<int>? highlightSet;

  List<Offset> _pathOf(int i, SchemeItem it) =>
      resolved?[i] ?? [for (final q in it.path) Offset(q.x, q.y)];

  @override
  void paint(Canvas canvas, Size size) {
    _paintField(canvas, size);
    final s = math.min(size.width, size.height);
    final items = [...scheme.items, ?preview];
    final multiStep = showSteps && scheme.steps.length > 1;
    // Сначала зоны и стрелки, сверху — игроки и инвентарь.
    final order = [
      for (var i = 0; i < items.length; i++)
        if (items[i].type == 'zone' || items[i].type == 'pen') i,
      for (var i = 0; i < items.length; i++)
        if (items[i].type.startsWith('arrow_')) i,
      for (var i = 0; i < items.length; i++)
        if (!items[i].isArrow) i,
    ];
    for (final e in ghosts?.entries ?? const <MapEntry<int, Offset>>[]) {
      if (e.key < 0 || e.key >= items.length) continue;
      final it = items[e.key];
      if ((Offset(it.x, it.y) - e.value).distance < 0.005) continue;
      canvas.saveLayer(null, Paint()..color = const Color.fromRGBO(0, 0, 0, 0.35));
      _paintItem(canvas, size, s, it.copyWith(x: e.value.dx, y: e.value.dy));
      canvas.restore();
    }
    for (final i in order) {
      var it = items[i];
      final pos = positions?[i];
      if (pos != null && !it.isArrow) {
        it = it.copyWith(x: pos.dx, y: pos.dy);
      }
      final dim = activeStep != null && it.isMovement && it.stepOrFirst != activeStep;
      if (dim) canvas.saveLayer(null, Paint()..color = const Color.fromRGBO(0, 0, 0, 0.25));
      if (it.isMovement) {
        if (i == selected) _arrowGlow(canvas, size, s, _pathOf(i, it));
        _arrow(canvas, [for (final q in _pathOf(i, it)) Offset(q.dx * size.width, q.dy * size.height)], it.type,
            s * 0.035, toPlayer: it.actor == null || it.target != null);
      } else {
        _paintItem(canvas, size, s, it, highlighted: i == selected || (highlightSet?.contains(i) ?? false));
      }
      if (dim) canvas.restore();
      if (multiStep && it.isMovement && positions == null) _stepBadge(canvas, size, s, _pathOf(i, it), it.stepOrFirst);
    }
    for (final e in positions?.entries ?? const <MapEntry<int, Offset>>[]) {
      if (e.key < 0) _paintItem(canvas, size, s, SchemeItem(type: 'ball', x: e.value.dx, y: e.value.dy));
    }
  }

  void _stepBadge(Canvas canvas, Size size, double s, List<Offset> path, int step) {
    final r = s * 0.022;
    final c0 = SchemeMove(0, path.length >= 2 ? path : [path.first, path.first]).at(0.5);
    final c = Offset(c0.dx * size.width, c0.dy * size.height);
    canvas.drawCircle(c, r, Paint()..color = Colors.black.withValues(alpha: 0.75));
    _text(canvas, '$step', c, r * 1.3, Colors.white);
  }

  void _arrowGlow(Canvas canvas, Size size, double s, List<Offset> path) {
    final p = Path()..moveTo(path.first.dx * size.width, path.first.dy * size.height);
    for (final q in path.skip(1)) {
      p.lineTo(q.dx * size.width, q.dy * size.height);
    }
    canvas.drawPath(
      p,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.035
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintField(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stripes = Paint();
    const n = 8;
    for (var i = 0; i < n; i++) {
      stripes.color = i.isEven ? SchemeColors.grass : SchemeColors.grassLight;
      canvas.drawRect(Rect.fromLTWH(0, h * i / n, w, h / n), stripes);
    }
    final line = Paint()
      ..color = SchemeColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, w / 250);
    final m = w * 0.03;
    final field = Rect.fromLTRB(m, m, w - m, h - m);
    canvas.drawRect(field, line);

    switch (scheme.field) {
      case 'full':
        // Горизонтальное поле: ворота слева и справа.
        canvas.drawLine(Offset(w / 2, field.top), Offset(w / 2, field.bottom), line);
        canvas.drawCircle(Offset(w / 2, h / 2), field.height * 0.14, line);
        for (final left in [true, false]) {
          final bw = field.width * 0.16, bh = field.height * 0.58;
          final sw = field.width * 0.055, sh = field.height * 0.27;
          final x = left ? field.left : field.right;
          canvas.drawRect(Rect.fromLTWH(left ? x : x - bw, h / 2 - bh / 2, bw, bh), line);
          canvas.drawRect(Rect.fromLTWH(left ? x : x - sw, h / 2 - sh / 2, sw, sh), line);
        }
      case 'full_v':
        // Вертикальное поле: свои ворота снизу, атака вверх.
        canvas.drawLine(Offset(field.left, h / 2), Offset(field.right, h / 2), line);
        canvas.drawCircle(Offset(w / 2, h / 2), field.width * 0.14, line);
        canvas.drawCircle(Offset(w / 2, h / 2), line.strokeWidth * 1.5, line..style = PaintingStyle.fill);
        line.style = PaintingStyle.stroke;
        for (final top in [true, false]) {
          final bw = field.width * 0.58, bh = field.height * 0.16;
          final sw = field.width * 0.27, sh = field.height * 0.055;
          final y = top ? field.top : field.bottom;
          canvas.drawRect(Rect.fromLTWH(w / 2 - bw / 2, top ? y : y - bh, bw, bh), line);
          canvas.drawRect(Rect.fromLTWH(w / 2 - sw / 2, top ? y : y - sh, sw, sh), line);
          final arc = Rect.fromCenter(
            center: Offset(w / 2, top ? y + bh : y - bh),
            width: field.width * 0.24,
            height: field.width * 0.16,
          );
          canvas.drawArc(arc, top ? 0 : math.pi, math.pi, false, line);
          final gw = field.width * 0.12;
          canvas.drawRect(
            Rect.fromLTWH(w / 2 - gw / 2, top ? y - m * 0.6 : y, gw, m * 0.6),
            Paint()..color = Colors.white.withValues(alpha: 0.5),
          );
        }
      case 'half':
      case 'third':
        // Ворота сверху.
        final bw = field.width * 0.62, bh = field.height * (scheme.field == 'half' ? 0.3 : 0.4);
        canvas.drawRect(Rect.fromLTWH(w / 2 - bw / 2, field.top, bw, bh), line);
        final sw = field.width * 0.28, sh = bh * 0.35;
        canvas.drawRect(Rect.fromLTWH(w / 2 - sw / 2, field.top, sw, sh), line);
        canvas.drawArc(
          Rect.fromCenter(center: Offset(w / 2, field.top + bh), width: field.width * 0.24, height: field.width * 0.16),
          0, math.pi, false, line,
        );
        if (scheme.field == 'half') {
          canvas.drawArc(Rect.fromCircle(center: Offset(w / 2, field.bottom), radius: field.height * 0.18), math.pi,
              math.pi, false, line);
        }
      case 'box':
        final sw = field.width * 0.45, sh = field.height * 0.3;
        canvas.drawRect(Rect.fromLTWH(w / 2 - sw / 2, field.top, sw, sh), line);
      default:
        // Площадка: только разметка фишками по углам, без линий поля.
        break;
    }
  }

  void _paintItem(Canvas canvas, Size size, double s, SchemeItem it, {bool highlighted = false}) {
    final p = Offset(it.x * size.width, it.y * size.height);
    final r = s * 0.035;
    if (highlighted) {
      canvas.drawCircle(p, r * 1.9, Paint()..color = Colors.white.withValues(alpha: 0.35));
    }
    switch (it.type) {
      case 'player_a' || 'player_b' || 'neutral' || 'goalkeeper':
        final color = switch (it.type) {
          'player_a' => SchemeColors.teamA,
          'player_b' => SchemeColors.teamB,
          'neutral' => SchemeColors.neutral,
          _ => SchemeColors.keeper,
        };
        canvas.drawCircle(p + Offset(0, r * 0.15), r, Paint()..color = Colors.black26);
        canvas.drawCircle(p, r, Paint()..color = color);
        canvas.drawCircle(
          p, r,
          Paint()
            ..color = it.type == 'player_b' ? Colors.black87 : Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.18,
        );
        if (it.label != null) {
          final dark = it.type == 'neutral' || it.type == 'player_b';
          // «9|Иванов»: номер в фишке, фамилия под ней.
          final parts = it.label!.split('|');
          _text(canvas, parts.first, p, r * (parts.first.length > 2 ? 0.8 : 1.1), dark ? Colors.black : Colors.white);
          if (parts.length > 1 && parts[1].isNotEmpty) {
            _caption(canvas, parts[1], p + Offset(0, r * 1.75), r * 0.85);
          }
        }
      case 'cone':
        final path = Path()
          ..moveTo(p.dx, p.dy - r * 0.8)
          ..lineTo(p.dx + r * 0.65, p.dy + r * 0.5)
          ..lineTo(p.dx - r * 0.65, p.dy + r * 0.5)
          ..close();
        canvas.drawPath(path, Paint()..color = SchemeColors.cone);
      case 'ball':
        canvas.drawCircle(p, r * 0.45, Paint()..color = Colors.white);
        canvas.drawCircle(
          p, r * 0.45,
          Paint()
            ..color = Colors.black87
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.1,
        );
        canvas.drawCircle(p, r * 0.15, Paint()..color = Colors.black87);
      case 'pole':
        canvas.drawLine(
          p.translate(0, -r * 0.9), p.translate(0, r * 0.6),
          Paint()
            ..color = SchemeColors.pole
            ..strokeWidth = r * 0.3
            ..strokeCap = StrokeCap.round,
        );
      case 'goal' || 'mini_goal':
        final gw = math.min((it.type == 'goal' ? 0.16 : 0.08) * size.width, r * (it.type == 'goal' ? 5 : 3));
        final gh = r * (it.type == 'goal' ? 0.7 : 0.55);
        final rect = Rect.fromCenter(center: p, width: gw, height: gh);
        canvas.drawRect(rect, Paint()..color = Colors.white24);
        canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.2,
        );
      case 'zone':
        final rect = Rect.fromPoints(p, Offset((it.x2 ?? it.x) * size.width, (it.y2 ?? it.y) * size.height));
        canvas.drawRect(rect, Paint()..color = Colors.white.withValues(alpha: 0.12));
        _dashedRect(canvas, rect, Paint()
          ..color = Colors.white70
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.12);
      case 'label':
        _text(canvas, it.label ?? '', p, r * 1.2, Colors.white);
      case 'pen':
        final pts = it.points ?? const [];
        if (pts.length < 2) break;
        final path = Path()..moveTo(pts.first.x * size.width, pts.first.y * size.height);
        for (final q in pts.skip(1)) {
          path.lineTo(q.x * size.width, q.y * size.height);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = parseHexColor(it.color) ?? Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      default:
        if (it.isMovement) {
          _arrow(canvas, [for (final q in it.path) Offset(q.x * size.width, q.y * size.height)], it.type, r);
        }
    }
  }

  /// Стрелка по ломаной: пунктир — бег, волна — ведение, сплошная — пас.
  void _arrow(Canvas canvas, List<Offset> pts0, String type, double r, {bool toPlayer = true}) {
    final pts = <Offset>[pts0.first];
    for (final q in pts0.skip(1)) {
      if ((q - pts.last).distance > 0.5) pts.add(q);
    }
    if (pts.length < 2) return;
    // Конец стрелки чуть раньше цели, чтобы наконечник не прятался под фишкой игрока.
    final lastSeg = pts.last - pts[pts.length - 2];
    if (lastSeg.distance > r * 4 && (toPlayer || type == 'arrow_pass')) {
      pts[pts.length - 1] = pts.last - lastSeg / lastSeg.distance * r * 1.1;
    }
    final paint = Paint()
      ..color = type == 'arrow_pass' ? Colors.white : const Color(0xFFFFF59D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Длины по ломаной.
    final cum = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + (pts[i] - pts[i - 1]).distance);
    }
    final len = cum.last;
    if (len < 2) return;
    Offset at(double t) {
      var i = 1;
      while (i < pts.length - 1 && cum[i] < t) {
        i++;
      }
      final seg = cum[i] - cum[i - 1];
      return Offset.lerp(pts[i - 1], pts[i], seg == 0 ? 1 : ((t - cum[i - 1]) / seg).clamp(0.0, 1.0))!;
    }

    Offset dirAt(double t) {
      final d = at(math.min(len, t + 1)) - at(math.max(0, t - 1));
      return d.distance == 0 ? const Offset(1, 0) : d / d.distance;
    }

    final stop = len - r * 0.5;
    switch (type) {
      case 'arrow_run':
        const dash = 8.0, gap = 6.0;
        for (var t = 0.0; t < stop; t += dash + gap) {
          canvas.drawLine(at(t), at(math.min(t + dash, stop)), paint);
        }
      case 'arrow_dribble':
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (var t = 4.0; t < stop; t += 4) {
          final d = dirAt(t);
          final q = at(t) + Offset(-d.dy, d.dx) * (math.sin(t / 6) * r * 0.35);
          path.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(path, paint);
      default:
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (var t = 6.0; t < stop; t += 6) {
          final q = at(t);
          path.lineTo(q.dx, q.dy);
        }
        final e = at(stop);
        path.lineTo(e.dx, e.dy);
        canvas.drawPath(path, paint);
    }
    final b = pts.last;
    final dir = dirAt(len - 2);
    final normal = Offset(-dir.dy, dir.dx);
    final head = Path()
      ..moveTo(b.dx, b.dy)
      ..lineTo((b - dir * r * 0.9 + normal * r * 0.45).dx, (b - dir * r * 0.9 + normal * r * 0.45).dy)
      ..lineTo((b - dir * r * 0.9 - normal * r * 0.45).dx, (b - dir * r * 0.9 - normal * r * 0.45).dy)
      ..close();
    canvas.drawPath(head, Paint()..color = paint.color);
  }

  void _dashedRect(Canvas canvas, Rect rect, Paint paint) {
    final corners = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft, rect.topLeft];
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[i + 1];
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var t = 0.0; t < len; t += 12) {
        canvas.drawLine(a + dir * t, a + dir * math.min(t + 7, len), paint);
      }
    }
  }

  /// Подпись под фишкой: светлый текст на тёмной плашке, читается на любой траве.
  void _caption(Canvas canvas, String text, Offset center, double size) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size * 9);
    final rect = Rect.fromCenter(center: center, width: tp.width + size * 0.8, height: tp.height + size * 0.2);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(size * 0.4)), Paint()..color = Colors.black.withValues(alpha: 0.55));
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _text(Canvas canvas, String text, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(SchemePainter old) =>
      old.scheme != scheme ||
      old.selected != selected ||
      old.preview != preview ||
      old.positions != positions ||
      old.activeStep != activeStep ||
      old.resolved != resolved ||
      old.ghosts != ghosts ||
      old.highlightSet != highlightSet;
}

Color? parseHexColor(String? hex) {
  if (hex == null || !hex.startsWith('#') || (hex.length != 7 && hex.length != 9)) return null;
  final v = int.tryParse(hex.substring(1), radix: 16);
  if (v == null) return null;
  return Color(hex.length == 7 ? 0xFF000000 | v : v);
}

/// Значок типа элемента для палитры редактора.
class SchemeItemIcon extends StatelessWidget {
  const SchemeItemIcon(this.type, {super.key, this.size = 36});

  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final item = type.startsWith('arrow_') || type == 'zone'
        ? SchemeItem(type: type, x: 0.15, y: 0.75, x2: 0.85, y2: 0.25)
        : SchemeItem(type: type, x: 0.5, y: 0.5, label: type == 'label' ? 'Aa' : null);
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(painter: _IconPainter(item)),
      ),
    );
  }
}

class _IconPainter extends SchemePainter {
  _IconPainter(SchemeItem item) : super(Scheme(field: 'grid', items: [item]), showSteps: false);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = SchemeColors.grass);
    final it = scheme.items.first;
    // Масштаб элемента для значка: на поле игрок ~3.5% площадки, в палитре — почти весь значок.
    final m = math.min(size.width, size.height);
    final s = switch (it.type) {
      'goal' || 'mini_goal' => m * 4,
      _ when it.isArrow => m * 3,
      _ => m * 9,
    };
    _paintItem(canvas, size, s, it);
  }
}
