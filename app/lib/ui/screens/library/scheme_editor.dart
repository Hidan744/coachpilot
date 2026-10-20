import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/scheme_animation.dart';
import '../../../data/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/scheme_view.dart';

/// Редактор схемы. Возвращает новую схему через Navigator.pop.
///
/// * «Выбор»: касание выбирает элемент, перетаскивание двигает его (игрок двигается вместе со своим мячом).
/// * Игроки и инвентарь: касание по полю ставит элемент. Мяч, поставленный у игрока, — его мяч.
/// * «Движение»: коснитесь игрока, выберите бег, ведение или пас и отмечайте путь точками по полю.
///   Пас — коснитесь партнёра. Каждое новое движение — следующий шаг анимации.
class SchemeEditorScreen extends StatefulWidget {
  const SchemeEditorScreen({super.key, this.initial});

  final Scheme? initial;

  @override
  State<SchemeEditorScreen> createState() => _SchemeEditorScreenState();
}

const _placeTools = ['player_a', 'player_b', 'neutral', 'goalkeeper', 'ball', 'cone', 'pole', 'goal', 'mini_goal', 'zone'];

const _moveLabels = {'arrow_run': 'Бег', 'arrow_dribble': 'Ведение', 'arrow_pass': 'Пас'};

var _idSeq = 0;
String _newObjectId() => 'o${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_idSeq++).toRadixString(36)}';

/// У каждого игрока и мяча — постоянный id, чтобы на него ссылались движения.
Scheme withObjectIds(Scheme s) => Scheme(
      field: s.field,
      items: [
        for (final it in s.items)
          (it.isPlayer || it.type == 'ball') && it.id == null ? it.copyWith(id: _newObjectId()) : it,
      ],
    );

class _SchemeEditorScreenState extends State<SchemeEditorScreen> {
  late Scheme _scheme = withObjectIds(widget.initial ?? const Scheme(field: 'half'));
  final _history = <Scheme>[];
  String _tool = 'select';
  int? _selected;
  Offset? _dragStart;
  SchemeItem? _preview;

  // Режим «Движение».
  int? _actor;
  String _moveType = 'arrow_run';
  List<Offset2> _path = [];

  /// Шаг анимации для нового движения.
  late int _step = _maxStep + 1;

  late SchemeAnimation _anim = SchemeAnimation(_scheme);

  int get _maxStep => _scheme.steps.fold(0, (a, b) => b > a ? b : a);

  void _set(Scheme next) {
    _scheme = next;
    _anim = SchemeAnimation(next);
  }

  void _commit(Scheme next) {
    _history.add(_scheme);
    if (_history.length > 50) _history.removeAt(0);
    setState(() => _set(next));
  }

  void _undo() {
    if (_path.isNotEmpty) {
      setState(() => _path.removeLast());
      return;
    }
    if (_history.isEmpty) return;
    setState(() {
      _set(_history.removeLast());
      _selected = null;
      _actor = null;
    });
  }

  SchemeItem? get _selectedArrow {
    final i = _selected;
    return i != null && i < _scheme.items.length && _scheme.items[i].isMovement ? _scheme.items[i] : null;
  }

  Offset _norm(Offset local, Size size) =>
      Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));

  double _dist(Offset a, Offset b, Size size) => Offset((a.dx - b.dx) * size.width / size.height, a.dy - b.dy).distance;

  /// Игрок под пальцем (с учётом того, где он стоит к выбранному шагу).
  int? _hitPlayer(Offset n, Size size, {Map<int, Offset>? at, int? except}) {
    int? best;
    var bestD = 0.07;
    for (var i = 0; i < _scheme.items.length; i++) {
      final it = _scheme.items[i];
      if (!it.isPlayer || i == except) continue;
      final d = _dist(at?[i] ?? Offset(it.x, it.y), n, size);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  int? _hit(Offset n, Size size) {
    int? best;
    var bestD = 0.06;
    for (var i = _scheme.items.length - 1; i >= 0; i--) {
      final it = _scheme.items[i];
      final pts = it.isMovement
          ? (_anim.resolvedPaths[i] ?? [for (final q in it.path) Offset(q.x, q.y)])
          : [Offset(it.x, it.y), if (it.type == 'zone') Offset(it.x2 ?? it.x, it.y2 ?? it.y)];
      for (final p in pts) {
        // Фишки важнее стрелок: у стрелок радиус меньше.
        final d = _dist(p, n, size) + (it.isMovement ? 0.015 : 0);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
    }
    return best;
  }

  int? _ballOf(String? playerId) {
    if (playerId == null) return null;
    final i = _scheme.items.indexWhere((e) => e.type == 'ball' && e.holder == playerId);
    return i < 0 ? null : i;
  }

  /// Есть ли мяч у игрока к началу шага, который сейчас рисуем.
  bool _hasBallAtStep(int actor) => _anim.holdersBeforeStep(_step).values.contains(actor);

  String? _nextLabel(String type) {
    if (type != 'player_a' && type != 'player_b') return null;
    return '${_scheme.items.where((e) => e.type == type).length + 1}';
  }

  // ------------------------------------------------------------ касания

  void _onTap(Offset local, Size size) {
    final n = _norm(local, size);
    switch (_tool) {
      case 'select':
        setState(() => _selected = _hit(n, size));
      case 'move':
        _moveTap(n, size);
      case 'zone':
        break;
      case 'ball':
        _placeBall(n, size);
      default:
        _commit(Scheme(field: _scheme.field, items: [
          ..._scheme.items,
          SchemeItem(
            type: _tool,
            x: n.dx,
            y: n.dy,
            label: _nextLabel(_tool),
            id: const {'player_a', 'player_b', 'neutral', 'goalkeeper'}.contains(_tool) ? _newObjectId() : null,
          ),
        ]));
    }
  }

  void _placeBall(Offset n, Size size) {
    final p = _hitPlayer(n, size);
    if (p == null) {
      _commit(Scheme(field: _scheme.field, items: [
        ..._scheme.items,
        SchemeItem(type: 'ball', x: n.dx, y: n.dy, id: _newObjectId()),
      ]));
      return;
    }
    final player = _scheme.items[p];
    if (_ballOf(player.id) != null) {
      showInfo(context, 'У этого игрока уже есть мяч');
      return;
    }
    _commit(Scheme(field: _scheme.field, items: [
      ..._scheme.items,
      SchemeItem(
        type: 'ball',
        x: player.x + ballOffset.dx,
        y: player.y + ballOffset.dy,
        id: _newObjectId(),
        holder: player.id,
      ),
    ]));
  }

  void _moveTap(Offset n, Size size) {
    final at = _anim.positionsBeforeStep(_step);
    final actor = _actor;
    if (actor == null) {
      final p = _hitPlayer(n, size, at: at);
      if (p == null) {
        showInfo(context, 'Коснитесь игрока, который будет двигаться');
        return;
      }
      setState(() {
        _actor = p;
        _moveType = _hasBallAtStep(p) ? 'arrow_dribble' : 'arrow_run';
        _path = [];
      });
      return;
    }
    // Пас — касанием партнёра.
    if (_moveType == 'arrow_pass') {
      final mate = _hitPlayer(n, size, at: _anim.positionsBeforeStep(_step), except: actor);
      if (mate != null) {
        final m = at[mate] ?? Offset(_scheme.items[mate].x, _scheme.items[mate].y);
        _finishMove(target: mate, end: Offset2(m.dx, m.dy));
        return;
      }
    }
    setState(() => _path.add(Offset2(n.dx, n.dy)));
  }

  void _finishMove({int? target, Offset2? end}) {
    final actor = _actor;
    if (actor == null) return;
    final start = _anim.positionsBeforeStep(_step)[actor] ?? Offset(_scheme.items[actor].x, _scheme.items[actor].y);
    final pts = [Offset2(start.dx, start.dy), ..._path, ?end];
    if (pts.length < 2) {
      showInfo(context, _moveType == 'arrow_pass' ? 'Коснитесь партнёра или точки, куда пас' : 'Отметьте на поле хотя бы одну точку');
      return;
    }
    final a = _scheme.items[actor];
    final arrow = SchemeItem(
      type: _moveType,
      x: pts.first.x,
      y: pts.first.y,
      x2: pts.last.x,
      y2: pts.last.y,
      points: pts.length > 2 ? pts : null,
      step: _step,
      actor: a.id,
      target: target == null ? null : _scheme.items[target].id,
    );
    _commit(Scheme(field: _scheme.field, items: [..._scheme.items, arrow]));
    setState(() {
      _actor = null;
      _path = [];
      _step = _maxStep + 1;
    });
  }

  void _onPanStart(Offset local, Size size) {
    final n = _norm(local, size);
    _dragStart = n;
    if (_tool == 'select') {
      final hit = _hit(n, size);
      setState(() => _selected = hit);
      if (hit != null) _history.add(_scheme);
    }
  }

  void _onPanUpdate(Offset local, Size size) {
    final n = _norm(local, size);
    final start = _dragStart;
    if (start == null) return;
    if (_tool == 'select') {
      final i = _selected;
      if (i == null) return;
      final it = _scheme.items[i];
      final dx = n.dx - start.dx, dy = n.dy - start.dy;
      final items = [..._scheme.items];
      items[i] = it.moved(dx, dy);
      // Мяч игрока двигается вместе с ним.
      if (it.isPlayer) {
        final b = _ballOf(it.id);
        if (b != null) items[b] = items[b].moved(dx, dy);
      }
      _dragStart = n;
      setState(() => _set(Scheme(field: _scheme.field, items: items)));
    } else if (_tool == 'zone') {
      setState(() => _preview = SchemeItem(type: 'zone', x: start.dx, y: start.dy, x2: n.dx, y2: n.dy));
    } else if (_tool == 'move' && _actor != null && _moveType != 'arrow_pass') {
      // Можно и провести пальцем: точки пути добавляются по ходу.
      final last = _path.isEmpty ? null : _path.last;
      if (last == null || (Offset(last.x, last.y) - n).distance > 0.04) setState(() => _path.add(Offset2(n.dx, n.dy)));
    }
  }

  void _onPanEnd(Size size) {
    final p = _preview;
    if (p != null && (Offset(p.x, p.y) - Offset(p.x2!, p.y2!)).distance > 0.03) {
      _commit(Scheme(field: _scheme.field, items: [..._scheme.items, p]));
    }
    // Мяч, отпущенный у игрока, становится его мячом; отпущенный в поле — свободным.
    final i = _selected;
    if (_tool == 'select' && i != null && _dragStart != null && _scheme.items[i].type == 'ball') {
      final ball = _scheme.items[i];
      final p = _hitPlayer(Offset(ball.x, ball.y), size);
      final owner = p == null ? null : _scheme.items[p];
      final items = [..._scheme.items];
      if (owner != null && (_ballOf(owner.id) == null || _ballOf(owner.id) == i)) {
        items[i] = ball.copyWith(x: owner.x + ballOffset.dx, y: owner.y + ballOffset.dy, holder: owner.id);
      } else {
        items[i] = ball.copyWith(holder: null);
      }
      setState(() => _set(Scheme(field: _scheme.field, items: items)));
    }
    setState(() {
      _preview = null;
      _dragStart = null;
    });
  }

  void _deleteSelected() {
    final i = _selected;
    if (i == null) return;
    final removed = _scheme.items[i];
    final items = <SchemeItem>[];
    for (var k = 0; k < _scheme.items.length; k++) {
      if (k == i) continue;
      var it = _scheme.items[k];
      if (removed.id != null) {
        // Движения удалённого игрока убираем, ссылки на него — очищаем.
        if (it.actor == removed.id) continue;
        if (it.target == removed.id) it = it.copyWith(target: null);
        if (it.holder == removed.id) it = it.copyWith(holder: null);
      }
      items.add(it);
    }
    _commit(Scheme(field: _scheme.field, items: items));
    setState(() => _selected = null);
  }

  void _setArrowStep(int step) {
    final i = _selected;
    if (i == null) return;
    final items = [..._scheme.items];
    items[i] = items[i].withStep(step);
    _commit(Scheme(field: _scheme.field, items: items));
  }

  void _play() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Нажмите ▶, чтобы увидеть движение', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
              child: SchemeView(_scheme),
            ),
          ]),
        ),
      );

  // ------------------------------------------------------------ интерфейс

  String get _hint {
    if (_tool == 'move') {
      if (_actor == null) return 'Движение, шаг $_step: коснитесь игрока, который двигается';
      final name = _scheme.items[_actor!].label ?? 'игрок';
      return switch (_moveType) {
        'arrow_pass' => 'Пас от $name: коснитесь партнёра (или точки на поле и ✓)',
        'arrow_dribble' => 'Ведение ($name с мячом): ставьте точки пути по полю, затем ✓',
        _ => 'Бег ($name без мяча): ставьте точки пути по полю, затем ✓',
      };
    }
    if (_tool == 'select') return 'Коснитесь элемента, чтобы выбрать; перетащите, чтобы передвинуть';
    if (_tool == 'ball') return 'Коснитесь игрока — мяч будет у него. Коснитесь поля — свободный мяч';
    if (_tool == 'zone') return 'Протяните пальцем по полю, чтобы отметить зону';
    return 'Коснитесь поля: ${schemeItemLabels[_tool]!.toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final actor = _actor;
    final drawingPath = _tool == 'move' && actor != null;
    final at = _anim.positionsBeforeStep(_step);
    final actorPos = actor == null ? null : (at[actor] ?? Offset(_scheme.items[actor].x, _scheme.items[actor].y));
    final preview = drawingPath && _path.isNotEmpty
        ? SchemeItem(
            type: _moveType,
            x: actorPos!.dx,
            y: actorPos.dy,
            points: [Offset2(actorPos.dx, actorPos.dy), ..._path],
          )
        : _preview;
    final mates = drawingPath && _moveType == 'arrow_pass'
        ? {for (var i = 0; i < _scheme.items.length; i++) if (_scheme.items[i].isPlayer && i != actor) i}
        : null;
    final hasBall = actor != null && _hasBallAtStep(actor);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Проиграть движение',
            onPressed: _scheme.items.any((e) => e.isMovement) ? _play : null,
            icon: const Icon(Icons.play_circle_outline),
          ),
          IconButton(
            tooltip: 'Отменить',
            onPressed: _history.isEmpty && _path.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Удалить выбранное',
            onPressed: _selected == null ? null : _deleteSelected,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Очистить',
            onPressed: _scheme.items.isEmpty ? null : () => _commit(Scheme(field: _scheme.field)),
            icon: const Icon(Icons.layers_clear_outlined),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => Navigator.pop(context, _scheme), child: const Text('Готово')),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final e in fieldLabels.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _scheme.field == e.key,
                    onSelected: (_) => _commit(Scheme(field: e.key, items: _scheme.items)),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AspectRatio(
                aspectRatio: fieldAspect(_scheme.field),
                child: LayoutBuilder(builder: (context, c) {
                  final size = Size(c.maxWidth, c.maxHeight);
                  return Semantics(
                    label: 'Поле схемы',
                    child: GestureDetector(
                      key: const Key('scheme_canvas'),
                      onTapUp: (d) => _onTap(d.localPosition, size),
                      onPanStart: (d) => _onPanStart(d.localPosition, size),
                      onPanUpdate: (d) => _onPanUpdate(d.localPosition, size),
                      onPanEnd: (_) => _onPanEnd(size),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CustomPaint(
                          size: size,
                          painter: SchemePainter(
                            _scheme,
                            selected: drawingPath ? actor : _selected,
                            preview: preview,
                            resolved: _anim.resolvedPaths,
                            ghosts: _tool == 'move' ? _anim.finalPositions : null,
                            highlightSet: mates,
                          ),
                          foregroundPainter: drawingPath ? _PointsPainter(actorPos!, _path) : null,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
        if (_tool == 'move') ...[
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                if (actor != null)
                  for (final e in _moveLabels.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: SchemeItemIcon(e.key, size: 22),
                        label: Text(e.value),
                        selected: _moveType == e.key,
                        // Вести мяч и отдать пас может только игрок с мячом.
                        onSelected: e.key != 'arrow_run' && !hasBall
                            ? null
                            : (_) => setState(() {
                                  _moveType = e.key;
                                  _path = [];
                                }),
                      ),
                    ),
                if (actor != null) const SizedBox(width: 8),
                Center(child: Text('Шаг:  ', style: t.textTheme.labelLarge)),
                for (var k = 1; k <= _maxStep + 1; k++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(k > _maxStep ? '$k (новый)' : '$k'),
                      selected: _step == k,
                      onSelected: (_) => setState(() {
                        _step = k;
                        _path = [];
                        if (_actor != null && !_hasBallAtStep(_actor!) && _moveType != 'arrow_run') _moveType = 'arrow_run';
                      }),
                    ),
                  ),
              ],
            ),
          ),
          if (drawingPath)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                TextButton.icon(
                  onPressed: () => setState(() {
                    _actor = null;
                    _path = [];
                  }),
                  icon: const Icon(Icons.close),
                  label: const Text('Отмена'),
                ),
                const Spacer(),
                Text('Точек: ${_path.length}', style: t.textTheme.bodySmall),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _path.isEmpty ? null : () => _finishMove(),
                  icon: const Icon(Icons.check),
                  label: const Text('Путь готов'),
                ),
              ]),
            ),
        ],
        if (_tool == 'select' && _selectedArrow != null)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                Center(child: Text('Шаг движения:  ', style: t.textTheme.labelLarge)),
                for (var k = 1; k <= _maxStep + 1; k++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('$k'),
                      selected: _selectedArrow!.stepOrFirst == k,
                      onSelected: (_) => _setArrowStep(k),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(_hint, style: t.textTheme.bodySmall, textAlign: TextAlign.center),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            // Все инструменты видны сразу: на поле некогда листать палитру.
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _ToolButton(
                  selected: _tool == 'select',
                  tooltip: 'Выбор и перемещение',
                  onTap: () => setState(() {
                    _tool = 'select';
                    _actor = null;
                    _path = [];
                  }),
                  child: const Icon(Icons.pan_tool_alt_outlined),
                ),
                _ToolButton(
                  selected: _tool == 'move',
                  tooltip: 'Движение игрока',
                  wide: true,
                  onTap: () => setState(() {
                    _tool = 'move';
                    _selected = null;
                    _step = _maxStep + 1;
                  }),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timeline, color: AppColors.red),
                    SizedBox(width: 4),
                    Text('Движение', style: TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
                for (final tool in _placeTools)
                  _ToolButton(
                    selected: _tool == tool,
                    tooltip: schemeItemLabels[tool]!,
                    onTap: () => setState(() {
                      _tool = tool;
                      _selected = null;
                      _actor = null;
                      _path = [];
                    }),
                    child: SchemeItemIcon(tool, size: 34),
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

/// Точки пути, которые тренер уже поставил: номера по порядку.
class _PointsPainter extends CustomPainter {
  _PointsPainter(this.start, this.points);

  final Offset start;
  final List<Offset2> points;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) * 0.018;
    canvas.drawCircle(Offset(start.dx * size.width, start.dy * size.height), r * 2.6,
        Paint()
          ..color = AppColors.red
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.5);
    for (var i = 0; i < points.length; i++) {
      final c = Offset(points[i].x * size.width, points[i].y * size.height);
      canvas.drawCircle(c, r, Paint()..color = AppColors.red);
      canvas.drawCircle(c, r, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.25);
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: TextStyle(color: Colors.white, fontSize: r * 1.2, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PointsPainter old) => old.start != start || old.points.length != points.length;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.selected, required this.tooltip, required this.onTap, required this.child, this.wide = false});

  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        selected: selected,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: wide ? null : 46,
            height: 46,
            padding: wide ? const EdgeInsets.symmetric(horizontal: 12) : null,
            alignment: wide ? null : Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 3 : 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
