import 'package:flutter/material.dart';

import '../../../data/models.dart';
import '../../widgets/scheme_view.dart';

/// Редактор схемы. Возвращает новую схему через Navigator.pop.
///
/// * Инструмент «Выбор»: касание выбирает элемент, перетаскивание двигает его.
/// * Игроки и инвентарь: касание по полю ставит элемент.
/// * Стрелки и зона: протяните пальцем от начала до конца.
class SchemeEditorScreen extends StatefulWidget {
  const SchemeEditorScreen({super.key, this.initial});

  final Scheme? initial;

  @override
  State<SchemeEditorScreen> createState() => _SchemeEditorScreenState();
}

const _tools = [
  'player_a', 'player_b', 'neutral', 'goalkeeper', 'ball', 'cone', 'pole', 'goal', 'mini_goal',
  'arrow_pass', 'arrow_run', 'arrow_dribble', 'zone',
];

class _SchemeEditorScreenState extends State<SchemeEditorScreen> {
  late Scheme _scheme = widget.initial ?? const Scheme(field: 'half');
  final _history = <Scheme>[];
  String _tool = 'select';
  int? _selected;
  Offset? _dragStart;
  SchemeItem? _preview;

  void _commit(Scheme next) {
    _history.add(_scheme);
    if (_history.length > 50) _history.removeAt(0);
    setState(() => _scheme = next);
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      _scheme = _history.removeLast();
      _selected = null;
    });
  }

  Offset _norm(Offset local, Size size) =>
      Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));

  int? _hit(Offset n, Size size) {
    final aspect = size.width / size.height;
    int? best;
    var bestDist = 0.06;
    for (var i = _scheme.items.length - 1; i >= 0; i--) {
      final it = _scheme.items[i];
      final points = [Offset(it.x, it.y), if (it.x2 != null) Offset((it.x + it.x2!) / 2, (it.y + it.y2!) / 2)];
      for (final p in points) {
        final d = Offset((p.dx - n.dx) * aspect, p.dy - n.dy).distance;
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
    }
    return best;
  }

  /// Номер для нового игрока своей команды.
  String? _nextLabel(String type) {
    if (type != 'player_a' && type != 'player_b') return null;
    return '${_scheme.items.where((e) => e.type == type).length + 1}';
  }

  void _onTap(Offset local, Size size) {
    final n = _norm(local, size);
    if (_tool == 'select') {
      setState(() => _selected = _hit(n, size));
      return;
    }
    if (_tool.startsWith('arrow_') || _tool == 'zone') return;
    _commit(Scheme(field: _scheme.field, items: [
      ..._scheme.items,
      SchemeItem(type: _tool, x: n.dx, y: n.dy, label: _nextLabel(_tool)),
    ]));
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
      final items = [..._scheme.items];
      items[i] = it.moved(n.dx - start.dx, n.dy - start.dy);
      _dragStart = n;
      setState(() => _scheme = Scheme(field: _scheme.field, items: items));
    } else if (_tool.startsWith('arrow_') || _tool == 'zone') {
      setState(() => _preview = SchemeItem(type: _tool, x: start.dx, y: start.dy, x2: n.dx, y2: n.dy));
    }
  }

  void _onPanEnd() {
    final p = _preview;
    if (p != null && (Offset(p.x, p.y) - Offset(p.x2!, p.y2!)).distance > 0.03) {
      _commit(Scheme(field: _scheme.field, items: [..._scheme.items, p]));
    }
    setState(() {
      _preview = null;
      _dragStart = null;
    });
  }

  void _deleteSelected() {
    final i = _selected;
    if (i == null) return;
    _commit(Scheme(field: _scheme.field, items: [..._scheme.items]..removeAt(i)));
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Схема'),
        actions: [
          IconButton(tooltip: 'Отменить', onPressed: _history.isEmpty ? null : _undo, icon: const Icon(Icons.undo)),
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
                  return GestureDetector(
                    key: const Key('scheme_canvas'),
                    onTapUp: (d) => _onTap(d.localPosition, size),
                    onPanStart: (d) => _onPanStart(d.localPosition, size),
                    onPanUpdate: (d) => _onPanUpdate(d.localPosition, size),
                    onPanEnd: (_) => _onPanEnd(),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CustomPaint(
                        size: size,
                        painter: SchemePainter(_scheme, selected: _selected, preview: _preview),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _tool == 'select'
                ? 'Коснитесь элемента, чтобы выбрать; перетащите, чтобы передвинуть'
                : _tool.startsWith('arrow_') || _tool == 'zone'
                    ? 'Протяните пальцем: ${schemeItemLabels[_tool]!.toLowerCase()}'
                    : 'Коснитесь поля: ${schemeItemLabels[_tool]!.toLowerCase()}',
            style: t.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            // Все инструменты видны сразу: на поле некогда листать палитру.
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _ToolButton(
                  selected: _tool == 'select',
                  tooltip: 'Выбор и перемещение',
                  onTap: () => setState(() => _tool = 'select'),
                  child: const Icon(Icons.pan_tool_alt_outlined),
                ),
                for (final tool in _tools)
                  _ToolButton(
                    selected: _tool == tool,
                    tooltip: schemeItemLabels[tool]!,
                    onTap: () => setState(() {
                      _tool = tool;
                      _selected = null;
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

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.selected, required this.tooltip, required this.onTap, required this.child});

  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
        message: tooltip,
        child: Semantics(
          label: tooltip,
          button: true,
          selected: selected,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
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
