import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/tactics.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/scheme_view.dart';
import 'lineup_screen.dart';

final boardsProvider = StreamProvider<List<TacticBoard>>((ref) => ref.watch(repoProvider).watchBoards());

// ---------------------------------------------------------------- список досок

class TacticsListScreen extends ConsumerWidget {
  const TacticsListScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final team = ref.read(currentTeamProvider);
    final id = await createBoard(ref, teamId: team?.id);
    if (context.mounted) context.push('/tactics/$id');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(boardsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Тактическая доска')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'board_add',
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Новая доска'),
      ),
      body: AsyncView(boards, builder: (all) {
        if (all.isEmpty) {
          return ListView(padding: const EdgeInsets.all(12), children: [
            const LineupEntryCard(),
            EmptyState(
              icon: Icons.draw_outlined,
              title: 'Объясняйте игру прямо на поле',
              text: 'Расставьте состав, нарисуйте пальцем движения, покажите замену. '
                  'Доска сохраняется и доступна на телефоне и планшете.',
              action: FilledButton.icon(
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Создать доску'),
              ),
            ),
          ]);
        }
        final list = [...all]..sort((a, b) => a.title.compareTo(b.title));
        return CustomScrollView(slivers: [
          const SliverPadding(padding: EdgeInsets.fromLTRB(12, 12, 12, 0), sliver: SliverToBoxAdapter(child: LineupEntryCard())),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final b = list[i];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push('/tactics/${b.id}'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: fieldAspect(b.scheme.field),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CustomPaint(painter: SchemePainter(b.scheme, showSteps: false)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (b.formation.isNotEmpty)
                            Text(b.formation, style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]);
      }),
    );
  }
}

/// Новая доска с расстановкой по возрасту команды и игроками состава на позициях.
Future<String> createBoard(WidgetRef ref, {String? teamId, String? matchId, String? title}) async {
  final repo = ref.read(repoProvider);
  final team = teamId == null ? null : await repo.get(Entities.teams, teamId, Team.fromJson);
  final players = team == null
      ? const <Player>[]
      : (await repo.list(Entities.players, Player.fromJson, parentId: team.id)).where((p) => p.active).toList();
  final f = _defaultFormation(team);
  final lineup = players.isEmpty ? const <Player?>[] : assignLineup(f, players);
  final board = TacticBoard(
    id: newId(),
    teamId: team?.id,
    matchId: matchId,
    title: title ?? 'Тактика $f',
    formation: f,
    scheme: Scheme(field: 'full_v', items: formationItems(f, lineup: lineup)),
  );
  await repo.put(Entities.boards, board);
  return board.id;
}

String _defaultFormation(Team? team) {
  final n = team?.defaultPlayers ?? 11;
  if (team != null && AgeGroups.age(team.ageGroup) <= 9) return n <= 6 ? '2-2' : '2-3-1';
  if (team != null && AgeGroups.age(team.ageGroup) <= 11) return '2-3-1';
  if (team != null && AgeGroups.age(team.ageGroup) <= 13) return '3-3-1';
  return '4-3-3';
}

// ---------------------------------------------------------------- доска

enum _Mode { move, draw, arrow, place }

const _penColors = {'#FFFFFF': 'Белый', '#FFEB3B': 'Жёлтый', '#E30613': 'Красный', '#4FC3F7': 'Голубой'};

class TacticBoardScreen extends ConsumerStatefulWidget {
  const TacticBoardScreen({super.key, required this.boardId});

  final String boardId;

  @override
  ConsumerState<TacticBoardScreen> createState() => _TacticBoardScreenState();
}

class _TacticBoardScreenState extends ConsumerState<TacticBoardScreen> {
  TacticBoard? _board;
  late Scheme _scheme;
  final _history = <Scheme>[];
  _Mode _mode = _Mode.move;
  String _arrowType = 'arrow_run';
  String _placeType = 'player_a';
  String _penColor = '#FFEB3B';
  int _step = 1;
  int? _drag;
  Offset? _last;
  List<Offset2>? _stroke;
  SchemeItem? _preview;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    ref.read(repoProvider).get(Entities.boards, widget.boardId, TacticBoard.fromJson).then((b) {
      if (!mounted) return;
      setState(() {
        _board = b;
        _missing = b == null;
        _scheme = b?.scheme ?? const Scheme(field: 'full_v');
      });
    });
  }

  Future<void> _save({String? title, String? formation, String? notes}) async {
    final b = _board;
    if (b == null) return;
    final next = TacticBoard(
      id: b.id,
      teamId: b.teamId,
      matchId: b.matchId,
      title: title ?? b.title,
      formation: formation ?? b.formation,
      scheme: _scheme,
      notes: notes ?? b.notes,
    );
    _board = next;
    await ref.read(repoProvider).put(Entities.boards, next);
  }

  void _commit(Scheme next, {bool save = true}) {
    _history.add(_scheme);
    if (_history.length > 60) _history.removeAt(0);
    setState(() => _scheme = next);
    if (save) _save();
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() => _scheme = _history.removeLast());
    _save();
  }

  Offset _norm(Offset local, Size size) =>
      Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));

  /// Ближайший объект под пальцем: фишки и мяч важнее стрелок и линий.
  int? _hit(Offset n, Size size, {bool tokensOnly = false}) {
    final aspect = size.width / size.height;
    double dist(Offset2 a) => Offset((a.x - n.dx) * aspect, a.y - n.dy).distance;
    int? best;
    var bestD = 0.065;
    for (var i = _scheme.items.length - 1; i >= 0; i--) {
      final it = _scheme.items[i];
      if (it.isArrow || it.type == 'pen') continue;
      final d = dist(Offset2(it.x, it.y));
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best != null || tokensOnly) return best;
    bestD = 0.04;
    for (var i = _scheme.items.length - 1; i >= 0; i--) {
      final it = _scheme.items[i];
      final pts = it.type == 'pen'
          ? it.points ?? const <Offset2>[]
          : it.isArrow
              ? [Offset2(it.x, it.y), Offset2((it.x + it.x2!) / 2, (it.y + it.y2!) / 2), Offset2(it.x2!, it.y2!)]
              : const <Offset2>[];
      for (final p in pts) {
        final d = dist(p);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
    }
    return best;
  }

  void _onTap(Offset local, Size size) {
    final n = _norm(local, size);
    switch (_mode) {
      case _Mode.place:
        if (_scheme.items.length >= 190) return showInfo(context, 'На доске слишком много элементов');
        final own = _placeType == 'player_a';
        _commit(Scheme(field: _scheme.field, items: [
          ..._scheme.items,
          SchemeItem(
            type: _placeType,
            x: n.dx,
            y: n.dy,
            label: own ? '${_scheme.items.where(isOwnToken).length + 1}' : null,
          ),
        ]));
      case _Mode.move:
        final i = _hit(n, size);
        if (i != null) _itemMenu(i);
      default:
        break;
    }
  }

  void _onPanStart(Offset local, Size size) {
    final n = _norm(local, size);
    _last = n;
    switch (_mode) {
      case _Mode.move:
        _drag = _hit(n, size, tokensOnly: true);
        if (_drag != null) _history.add(_scheme);
      case _Mode.draw:
        _stroke = [Offset2(n.dx, n.dy)];
      default:
        break;
    }
  }

  void _onPanUpdate(Offset local, Size size) {
    final n = _norm(local, size);
    final start = _last;
    if (start == null) return;
    switch (_mode) {
      case _Mode.move:
        final i = _drag;
        if (i == null) return;
        final items = [..._scheme.items];
        items[i] = items[i].moved(n.dx - start.dx, n.dy - start.dy);
        _last = n;
        setState(() => _scheme = Scheme(field: _scheme.field, items: items));
      case _Mode.draw:
        setState(() => _stroke = [...?_stroke, Offset2(n.dx, n.dy)]);
      case _Mode.arrow:
        setState(() => _preview = SchemeItem(type: _arrowType, x: start.dx, y: start.dy, x2: n.dx, y2: n.dy, step: _step));
      case _Mode.place:
        break;
    }
  }

  void _onPanEnd() {
    switch (_mode) {
      case _Mode.move:
        if (_drag != null) _save();
      case _Mode.draw:
        final pts = simplifyStroke(_stroke ?? const []);
        if (pts.length >= 2) {
          _commit(Scheme(field: _scheme.field, items: [
            ..._scheme.items,
            SchemeItem(type: 'pen', x: pts.first.x, y: pts.first.y, points: pts, color: _penColor),
          ]));
        }
      case _Mode.arrow:
        final p = _preview;
        if (p != null && (Offset(p.x, p.y) - Offset(p.x2!, p.y2!)).distance > 0.03) {
          _commit(Scheme(field: _scheme.field, items: [..._scheme.items, p]));
        }
      case _Mode.place:
        break;
    }
    setState(() {
      _drag = null;
      _last = null;
      _stroke = null;
      _preview = null;
    });
  }

  // ------------------------------------------------------------ действия

  Future<List<Player>> _teamPlayers() async {
    final teamId = _board?.teamId;
    if (teamId == null) return const [];
    final all = await ref.read(repoProvider).list(Entities.players, Player.fromJson, parentId: teamId);
    return all.where((p) => p.active).toList()
      ..sort((a, b) => (a.number ?? 999).compareTo(b.number ?? 999));
  }

  /// Игроки команды, которых нет на поле, — скамейка для замен.
  Future<List<Player>> _bench() async {
    final onField = _scheme.items.where(isOwnToken).map((e) => e.label).toSet();
    return (await _teamPlayers()).where((p) => !onField.contains(tokenLabel(p))).toList();
  }

  void _itemMenu(int i) {
    final it = _scheme.items[i];
    final own = isOwnToken(it);
    final name = it.label?.split('|').last;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (it.label != null)
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(name ?? '', style: Theme.of(c).textTheme.titleMedium)),
          if (own)
            ListTile(
              leading: const Icon(Icons.swap_vert, color: AppColors.red),
              title: const Text('Замена'),
              subtitle: const Text('Выбрать игрока со скамейки'),
              onTap: () {
                Navigator.pop(c);
                _substitute(i);
              },
            ),
          if (it.isPlayer)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Подписать'),
              onTap: () {
                Navigator.pop(c);
                _rename(i);
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Убрать с поля'),
            onTap: () {
              Navigator.pop(c);
              _commit(Scheme(field: _scheme.field, items: [..._scheme.items]..removeAt(i)));
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _substitute(int i) async {
    final bench = await _bench();
    if (!mounted) return;
    if (bench.isEmpty) {
      return showInfo(context, _board?.teamId == null ? 'Доска не привязана к команде' : 'На скамейке никого нет');
    }
    final out = _scheme.items[i];
    final p = await showModalBottomSheet<Player>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (c, scroll) => ListView(controller: scroll, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Кто выходит вместо ${out.label?.split('|').last ?? 'игрока'}?',
                style: Theme.of(c).textTheme.titleMedium),
          ),
          for (final b in bench)
            ListTile(
              leading: CircleAvatar(child: Text(b.number?.toString() ?? '—')),
              title: Text(b.fullName),
              subtitle: Text(Positions.all[b.position] ?? ''),
              onTap: () => Navigator.pop(c, b),
            ),
        ]),
      ),
    );
    if (p == null) return;
    final items = [..._scheme.items];
    items[i] = items[i].withLabel(tokenLabel(p));
    _commit(Scheme(field: _scheme.field, items: items), save: false);
    final line = 'Замена: вышел ${p.lastName.isNotEmpty ? p.lastName : p.firstName}, ушёл ${out.label?.split('|').last ?? '?'}';
    final notes = [if ((_board?.notes ?? '').isNotEmpty) _board!.notes, line].join('\n');
    await _save(notes: notes);
    if (mounted) showInfo(context, line);
  }

  Future<void> _rename(int i) async {
    final it = _scheme.items[i];
    final parts = (it.label ?? '').split('|');
    final num = TextEditingController(text: parts.first);
    final name = TextEditingController(text: parts.length > 1 ? parts[1] : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Подпись игрока'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: num, decoration: const InputDecoration(labelText: 'Номер'), maxLength: 3),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Фамилия'), maxLength: 20),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Готово')),
        ],
      ),
    );
    if (ok != true) return;
    final label = name.text.trim().isEmpty ? num.text.trim() : '${num.text.trim()}|${name.text.trim()}';
    final items = [..._scheme.items];
    items[i] = items[i].withLabel(label.isEmpty ? null : label);
    _commit(Scheme(field: _scheme.field, items: items));
  }

  Future<void> _formationMenu() async {
    var opponent = false;
    final picked = await showModalBottomSheet<(String, bool)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            Text('Расстановка', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Своя команда')),
                ButtonSegment(value: true, label: Text('Соперник')),
              ],
              selected: {opponent},
              onSelectionChanged: (s) => set(() => opponent = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              opponent
                  ? 'Белые фишки соперника встанут на его половине.'
                  : 'Игроки команды встанут по позициям: вратарь, защитники, полузащитники, нападающие.',
              style: Theme.of(c).textTheme.bodySmall,
            ),
            for (final g in formations.entries) ...[
              Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(g.key, style: Theme.of(c).textTheme.labelLarge)),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in g.value)
                  ActionChip(label: Text(f), onPressed: () => Navigator.pop(c, (f, opponent))),
              ]),
            ],
          ]),
        ),
      ),
    );
    if (picked == null) return;
    final (f, opp) = picked;
    final vertical = _scheme.field == 'full_v';
    var base = vertical ? _scheme : rotateBoard(_scheme);
    final keep = base.items.where((it) => opp ? it.type != 'player_b' : !isOwnToken(it)).toList();
    List<Player?> lineup = const [];
    if (!opp) {
      // Те, кто уже на поле, остаются в составе; остальных добираем из команды.
      final players = await _teamPlayers();
      final onField = base.items.where(isOwnToken).map((e) => e.label).toSet();
      final ordered = [
        ...players.where((p) => onField.contains(tokenLabel(p))),
        ...players.where((p) => !onField.contains(tokenLabel(p))),
      ];
      lineup = ordered.isEmpty ? const [] : assignLineup(f, ordered);
    }
    base = Scheme(field: 'full_v', items: [...keep, ...formationItems(f, lineup: lineup, opponent: opp)]);
    _commit(vertical ? base : rotateBoard(base), save: false);
    await _save(formation: opp ? null : f);
    setState(() {});
  }

  void _clearMenu() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.gesture),
              title: const Text('Стереть рисунки и стрелки'),
              subtitle: const Text('Игроки останутся на местах'),
              onTap: () {
                Navigator.pop(c);
                _commit(Scheme(field: _scheme.field, items: _scheme.items.where((e) => !e.isArrow && e.type != 'pen').toList()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: const Text('Очистить всё поле'),
              onTap: () {
                Navigator.pop(c);
                _commit(Scheme(field: _scheme.field));
              },
            ),
          ]),
        ),
      );

  Future<void> _renameBoard() async {
    final c = TextEditingController(text: _board?.title);
    final notes = TextEditingController(text: _board?.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Доска'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: c, decoration: const InputDecoration(labelText: 'Название'), autofocus: true),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Заметки и замены'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      await _save(title: c.text.trim(), notes: notes.text.trim());
      setState(() {});
    }
  }

  void _play() => showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Expanded(child: Text('Нажмите ▶, чтобы показать движение', style: TextStyle(fontWeight: FontWeight.w600))),
                IconButton(tooltip: 'Закрыть', onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
              ]),
              Flexible(child: SchemeView(_scheme)),
            ]),
          ),
        ),
      );

  // ------------------------------------------------------------ интерфейс

  String get _hint => switch (_mode) {
        _Mode.move => 'Перетащите фишку пальцем. Касание — замена, подпись, удалить.',
        _Mode.draw => 'Рисуйте пальцем по полю',
        _Mode.arrow => 'Протяните стрелку от игрока. Стрелки одного шага двигаются одновременно.',
        _Mode.place => 'Коснитесь поля, чтобы поставить: ${schemeItemLabels[_placeType]!.toLowerCase()}',
      };

  @override
  Widget build(BuildContext context) {
    if (_missing) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.draw_outlined, title: 'Доска удалена'));
    final board = _board;
    if (board == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final t = Theme.of(context);
    final steps = _scheme.steps;
    final maxStep = steps.isEmpty ? 1 : steps.last;
    final strokeItem = _stroke != null && _stroke!.length > 1
        ? SchemeItem(type: 'pen', x: _stroke!.first.x, y: _stroke!.first.y, points: _stroke, color: _penColor)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _renameBoard,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(board.title, overflow: TextOverflow.ellipsis),
            if (board.formation.isNotEmpty) Text(board.formation, style: t.textTheme.bodySmall),
          ]),
        ),
        actions: [
          IconButton(
            tooltip: 'Показать движение',
            onPressed: _scheme.items.any((e) => e.isMovement) ? _play : null,
            icon: const Icon(Icons.play_circle_outline),
          ),
          IconButton(tooltip: 'Отменить', onPressed: _history.isEmpty ? null : _undo, icon: const Icon(Icons.undo)),
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            onSelected: (v) async {
              switch (v) {
                case 'rotate':
                  _commit(rotateBoard(_scheme));
                case 'rename':
                  _renameBoard();
                case 'clear':
                  _clearMenu();
                case 'delete':
                  if (await confirm(context, 'Удалить доску?')) {
                    await ref.read(repoProvider).remove(Entities.boards, board.id);
                    if (context.mounted) popOr(context, '/tactics');
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rotate', child: Text('Повернуть поле')),
              PopupMenuItem(value: 'rename', child: Text('Название и заметки')),
              PopupMenuItem(value: 'clear', child: Text('Очистить')),
              PopupMenuItem(value: 'delete', child: Text('Удалить доску')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: AspectRatio(
                  aspectRatio: fieldAspect(_scheme.field),
                  child: LayoutBuilder(builder: (context, c) {
                    final size = Size(c.maxWidth, c.maxHeight);
                    return Semantics(
                      label: 'Поле тактической доски',
                      child: GestureDetector(
                        key: const Key('board_canvas'),
                        onTapUp: (d) => _onTap(d.localPosition, size),
                        onPanStart: (d) => _onPanStart(d.localPosition, size),
                        onPanUpdate: (d) => _onPanUpdate(d.localPosition, size),
                        onPanEnd: (_) => _onPanEnd(),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CustomPaint(
                            size: size,
                            painter: SchemePainter(
                              Scheme(field: _scheme.field, items: [..._scheme.items, ?strokeItem]),
                              selected: _drag,
                              preview: _preview,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          if (_mode == _Mode.draw)
            _OptionsRow(children: [
              for (final e in _penColors.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Semantics(
                    label: 'Цвет: ${e.value}',
                    selected: _penColor == e.key,
                    button: true,
                    child: InkWell(
                      onTap: () => setState(() => _penColor = e.key),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: parseHexColor(e.key),
                          shape: BoxShape.circle,
                          border: Border.all(color: _penColor == e.key ? Colors.white : AppColors.outline, width: _penColor == e.key ? 3 : 1),
                        ),
                      ),
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: _scheme.items.any((e) => e.type == 'pen')
                    ? () => _commit(Scheme(field: _scheme.field, items: _scheme.items.where((e) => e.type != 'pen').toList()))
                    : null,
                icon: const Icon(Icons.auto_fix_normal),
                label: const Text('Стереть рисунки'),
              ),
            ]),
          if (_mode == _Mode.arrow)
            _OptionsRow(children: [
              for (final a in const ['arrow_run', 'arrow_pass', 'arrow_dribble'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: SchemeItemIcon(a, size: 22),
                    label: Text(schemeItemLabels[a]!),
                    selected: _arrowType == a,
                    onSelected: (_) => setState(() => _arrowType = a),
                  ),
                ),
              const SizedBox(width: 8),
              for (var k = 1; k <= maxStep + 1; k++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(k > maxStep ? '+ шаг $k' : 'шаг $k'),
                    selected: _step == k,
                    onSelected: (_) => setState(() => _step = k),
                  ),
                ),
            ]),
          if (_mode == _Mode.place)
            _OptionsRow(children: [
              for (final p in const ['player_a', 'player_b', 'goalkeeper', 'ball', 'cone', 'mini_goal'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: SchemeItemIcon(p, size: 22),
                    label: Text(switch (p) {
                      'player_a' => 'Свой',
                      'player_b' => 'Соперник',
                      _ => schemeItemLabels[p]!,
                    }),
                    selected: _placeType == p,
                    onSelected: (_) => setState(() => _placeType = p),
                  ),
                ),
            ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_hint, style: t.textTheme.bodySmall, textAlign: TextAlign.center),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              _ModeButton(icon: Icons.pan_tool_alt_outlined, label: 'Двигать', selected: _mode == _Mode.move, onTap: () => setState(() => _mode = _Mode.move)),
              _ModeButton(icon: Icons.brush_outlined, label: 'Рисовать', selected: _mode == _Mode.draw, onTap: () => setState(() => _mode = _Mode.draw)),
              _ModeButton(icon: Icons.north_east, label: 'Стрелка', selected: _mode == _Mode.arrow, onTap: () => setState(() => _mode = _Mode.arrow)),
              _ModeButton(icon: Icons.add_circle_outline, label: 'Добавить', selected: _mode == _Mode.place, onTap: () => setState(() => _mode = _Mode.place)),
              _ModeButton(icon: Icons.grid_view, label: 'Схема', selected: false, onTap: _formationMenu),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _OptionsRow extends StatelessWidget {
  const _OptionsRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          children: [Row(children: children)],
        ),
      );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          label: label,
          button: true,
          selected: selected,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.red : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: Colors.white),
                const SizedBox(height: 2),
                FittedBox(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white))),
              ]),
            ),
          ),
        ),
      );
}

