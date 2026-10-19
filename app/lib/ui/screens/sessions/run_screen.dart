import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/providers.dart';
import '../../../core/run_state.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../widgets/common.dart';
import '../../widgets/scheme_view.dart';
import '../library/library_screens.dart';
import 'sessions_screens.dart';

/// Режим проведения занятия: крупный таймер, текущий блок, схема и подсказки.
/// Работает полностью офлайн; состояние хранится на телефоне.
class RunScreen extends ConsumerStatefulWidget {
  const RunScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends ConsumerState<RunScreen> with WidgetsBindingObserver {
  RunState? _run;
  Timer? _ticker;
  bool _signalled = false;
  TrainingSession? _session;

  String get _key => 'run:${widget.sessionId}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await ref.read(dbProvider).getKv(_key);
    final s = await ref.read(repoProvider).get(Entities.sessions, widget.sessionId, TrainingSession.fromJson);
    if (!mounted) return;
    setState(() {
      _session = s;
      _run = saved == null ? RunState() : RunState.decode(saved);
    });
  }

  Future<void> _persist() async {
    final r = _run;
    if (r == null) return;
    await ref.read(dbProvider).setKv(_key, r.encode());
  }

  void _tick() {
    final r = _run, s = _session;
    if (r == null || s == null || !r.running || r.finished) return;
    final b = s.blocks[r.index];
    if (!_signalled && r.remaining(b, DateTime.now()) <= Duration.zero) {
      _signalled = true;
      _signal();
    }
    setState(() {});
  }

  Future<void> _signal() async {
    for (var i = 0; i < 3; i++) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  Future<void> _toggle() async {
    final r = _run!, s = _session!;
    final now = DateTime.now();
    if (r.running) {
      r.pause(now);
    } else {
      r.start(now);
      if (s.status != 'in_progress') {
        final started = s.copyWith(status: 'in_progress', startedAt: s.startedAt ?? now);
        _session = started;
        await ref.read(repoProvider).put(Entities.sessions, started);
      }
    }
    await _persist();
    setState(() {});
  }

  Future<void> _next({bool skip = false}) async {
    final r = _run!, s = _session!;
    final done = r.next(s.blocks, DateTime.now(), skip: skip);
    _signalled = false;
    await _persist();
    if (done) {
      await _finish();
    } else {
      setState(() {});
    }
  }

  Future<void> _finish() async {
    final r = _run!, s = _session!;
    final now = DateTime.now();
    if (!r.finished) {
      r.next(s.blocks, now);
      // досрочное завершение: оставшиеся блоки отмечаем пропущенными
      for (final b in s.blocks) {
        if (!r.actualSec.containsKey(b.id)) r.skipped.add(b.id);
      }
    }
    final finished = s.copyWith(status: 'done', startedAt: s.startedAt ?? now, finishedAt: now, actual: r.toActual());
    await ref.read(repoProvider).put(Entities.sessions, finished);
    await ref.read(dbProvider).deleteKv(_key);
    if (mounted) context.pushReplacement('/sessions/${s.id}/report');
  }

  Future<void> _note(TrainingBlock b) async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _QuickNoteSheet(blockTitle: b.title),
    );
    if (text == null || text.trim().isEmpty) return;
    await ref.read(repoProvider).put(
          Entities.notes,
          SessionNote(id: newId(), sessionId: widget.sessionId, blockId: b.id, text: text.trim(), notedAt: DateTime.now()),
        );
    if (mounted) showInfo(context, 'Заметка сохранена');
  }

  @override
  Widget build(BuildContext context) {
    final r = _run, s = _session;
    if (r == null || s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (s.blocks.isEmpty) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.event_busy, title: 'В плане нет блоков'));
    final t = Theme.of(context);
    final now = DateTime.now();
    final b = s.blocks[r.index];
    final drill = b.drillSnapshot;
    final remaining = r.remaining(b, now);
    final over = remaining.isNegative;
    final progress = (r.elapsed(now).inMilliseconds / r.planned(b).inMilliseconds).clamp(0.0, 1.0);
    final color = phaseColors[b.phase]!;
    final nextBlock = r.index + 1 < s.blocks.length ? s.blocks[r.index + 1] : null;
    // Компактные кнопки: на узких экранах подписи не должны переноситься по слогам.
    const compact = EdgeInsets.symmetric(horizontal: 6);
    final outlined = OutlinedButton.styleFrom(padding: compact, minimumSize: const Size(48, 52));

    return Scaffold(
      appBar: AppBar(
        title: Text('${r.index + 1} / ${s.blocks.length} · ${Phases.all[b.phase]}'),
        actions: [
          IconButton(
            tooltip: 'Предыдущий блок',
            onPressed: r.index == 0
                ? null
                : () async {
                    r.back(s.blocks, DateTime.now());
                    _signalled = false;
                    await _persist();
                    setState(() {});
                  },
            icon: const Icon(Icons.skip_previous),
          ),
          TextButton(
            onPressed: () async {
              if (await confirm(context, 'Завершить занятие?', text: 'Оставшиеся блоки будут отмечены как пропущенные.', ok: 'Завершить')) {
                await _finish();
              }
            },
            child: const Text('Завершить'),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        Text(b.title, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: SizedBox.square(
            dimension: 230,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 14,
                  color: over ? t.colorScheme.error : color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  formatClock(remaining),
                  key: const Key('run_clock'),
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: over ? t.colorScheme.error : null,
                  ),
                ),
                Text(r.running ? (over ? 'время вышло' : 'осталось') : 'пауза', style: t.textTheme.titleMedium),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: outlined,
              onPressed: () async {
                r.adjust(b, -1);
                await _persist();
                setState(() {});
              },
              child: const Text('−1 мин', maxLines: 1, softWrap: false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              key: const Key('run_toggle'),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 64), backgroundColor: r.running ? Colors.orange.shade800 : null),
              onPressed: _toggle,
              icon: Icon(r.running ? Icons.pause : Icons.play_arrow, size: 32),
              label: FittedBox(
                child: Text(
                  r.running ? 'Пауза' : (r.elapsed(now) == Duration.zero ? 'Старт' : 'Продолжить'),
                  maxLines: 1,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: outlined,
              onPressed: () async {
                r.adjust(b, 1);
                _signalled = r.remaining(b, DateTime.now()) <= Duration.zero;
                await _persist();
                setState(() {});
              },
              child: const Text('+1 мин', maxLines: 1, softWrap: false),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: outlined,
              onPressed: () => _note(b),
              icon: const Icon(Icons.edit_note, size: 20),
              label: const Text('Заметка', maxLines: 1, softWrap: false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: outlined,
              onPressed: () => _next(skip: true),
              icon: const Icon(Icons.redo, size: 20),
              label: const FittedBox(child: Text('Пропустить', maxLines: 1)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              key: const Key('run_next'),
              style: FilledButton.styleFrom(padding: compact, minimumSize: const Size(48, 52)),
              onPressed: () => _next(),
              icon: Icon(nextBlock == null ? Icons.flag : Icons.skip_next),
              label: Text(nextBlock == null ? 'Финиш' : 'Далее'),
            ),
          ),
        ]),
        if (nextBlock != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Дальше: ${nextBlock.title} · ${nextBlock.durationMin} мин',
                style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
          ),
        if (b.notes.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 16),
            color: t.colorScheme.secondaryContainer,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(b.notes, style: t.textTheme.bodyLarge)),
          ),
        if (drill?.scheme != null && drill!.scheme!.items.isNotEmpty) ...[
          const SizedBox(height: 16),
          SchemeView(drill.scheme!),
        ],
        if (drill != null && drill.coachingPoints.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Подсказки', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          for (final p in drill.coachingPoints.take(4))
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $p', style: t.textTheme.titleMedium)),
        ],
        if (drill != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.description_outlined),
              label: const Text('Полное описание'),
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (c) => DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.85,
                  builder: (c, scroll) => ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    children: [DrillDetails(drill, compact: true)],
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() {});
  }
}

class _QuickNoteSheet extends StatefulWidget {
  const _QuickNoteSheet({required this.blockTitle});

  final String blockTitle;

  @override
  State<_QuickNoteSheet> createState() => _QuickNoteSheetState();
}

class _QuickNoteSheetState extends State<_QuickNoteSheet> {
  final _c = TextEditingController();

  static const quick = [
    'Хорошо получилось',
    'Не поняли задание',
    'Низкая интенсивность',
    'Слишком сложно',
    'Слишком легко',
    'Нужно больше места',
  ];

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Заметка: ${widget.blockTitle}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final q in quick)
              ActionChip(label: Text(q), onPressed: () => Navigator.pop(context, q)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: false,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Своя заметка'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Сохранить заметку')),
        ]),
      );
}
