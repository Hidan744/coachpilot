import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Пропорции площадки (ширина / высота) для каждого типа поля.
double fieldAspect(String field) => switch (field) {
      'full' => 1.5,
      'half' => 1.25,
      'third' => 1.25,
      'box' => 1.6,
      _ => 1.2,
    };

const fieldLabels = {
  'full': 'Всё поле',
  'half': 'Половина',
  'third': 'Треть',
  'box': 'Штрафная',
  'grid': 'Площадка',
};

const schemeItemLabels = {
  'player_a': 'Игрок (синие)',
  'player_b': 'Игрок (красные)',
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
};

class SchemeColors {
  static const grass = Color(0xFF2E7D32);
  static const grassLight = Color(0xFF388E3C);
  static const line = Color(0xE6FFFFFF);
  static const teamA = Color(0xFF1565C0);
  static const teamB = Color(0xFFD32F2F);
  static const neutral = Color(0xFFFBC02D);
  static const keeper = Color(0xFF212121);
  static const cone = Color(0xFFFF6D00);
  static const pole = Color(0xFFFFEB3B);
}

/// Схема упражнения: только просмотр. Для редактирования — SchemeEditor.
class SchemeView extends StatelessWidget {
  const SchemeView(this.scheme, {super.key, this.selected});

  final Scheme scheme;
  final int? selected;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: fieldAspect(scheme.field),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CustomPaint(painter: SchemePainter(scheme, selected: selected)),
        ),
      );
}

class SchemePainter extends CustomPainter {
  SchemePainter(this.scheme, {this.selected, this.preview});

  final Scheme scheme;
  final int? selected;

  /// Стрелка, которую пользователь тянет прямо сейчас.
  final SchemeItem? preview;

  @override
  void paint(Canvas canvas, Size size) {
    _paintField(canvas, size);
    final s = math.min(size.width, size.height);
    final items = [...scheme.items, ?preview];
    // Сначала зоны и стрелки, сверху — игроки и инвентарь.
    final order = [
      for (var i = 0; i < items.length; i++)
        if (items[i].type == 'zone') i,
      for (var i = 0; i < items.length; i++)
        if (items[i].type.startsWith('arrow_')) i,
      for (var i = 0; i < items.length; i++)
        if (!items[i].isArrow) i,
    ];
    for (final i in order) {
      _paintItem(canvas, size, s, items[i], highlighted: i == selected);
    }
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
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.18,
        );
        if (it.label != null) {
          _text(canvas, it.label!, p, r * 1.1, it.type == 'neutral' ? Colors.black : Colors.white);
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
      default:
        if (it.type.startsWith('arrow_') && it.x2 != null && it.y2 != null) {
          _arrow(canvas, p, Offset(it.x2! * size.width, it.y2! * size.height), it.type, r);
        }
    }
  }

  void _arrow(Canvas canvas, Offset a, Offset b0, String type, double r) {
    // Конец стрелки чуть раньше цели, чтобы наконечник не прятался под фишкой игрока.
    final full = b0 - a;
    final b = full.distance > r * 4 ? b0 - full / full.distance * r * 1.1 : b0;
    final paint = Paint()
      ..color = type == 'arrow_pass' ? Colors.white : const Color(0xFFFFF59D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.22
      ..strokeCap = StrokeCap.round;
    final d = b - a;
    final len = d.distance;
    if (len < 2) return;
    final dir = d / len;
    final normal = Offset(-dir.dy, dir.dx);
    final end = b - dir * r * 0.4;
    switch (type) {
      case 'arrow_run':
        // Пунктир: бег без мяча.
        const dash = 8.0, gap = 6.0;
        var t = 0.0;
        while (t < len - r) {
          final t2 = math.min(t + dash, len - r * 0.4);
          canvas.drawLine(a + dir * t, a + dir * t2, paint);
          t += dash + gap;
        }
      case 'arrow_dribble':
        // Волна: ведение мяча.
        final path = Path()..moveTo(a.dx, a.dy);
        const step = 4.0;
        for (var t = step; t < len - r * 0.4; t += step) {
          final o = math.sin(t / 6) * r * 0.35;
          final q = a + dir * t + normal * o;
          path.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(path, paint);
      default:
        canvas.drawLine(a, end, paint);
    }
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

  void _text(Canvas canvas, String text, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(SchemePainter old) =>
      old.scheme != scheme || old.selected != selected || old.preview != preview;
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
  _IconPainter(SchemeItem item) : super(Scheme(field: 'grid', items: [item]));

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
