import 'dart:convert';

import '../data/models.dart';

/// Состояние проведения занятия. Время считается по меткам, а не по тикам таймера,
/// поэтому оно верно после сворачивания приложения, блокировки экрана или перезапуска.
class RunState {
  RunState({
    this.index = 0,
    this.startedAtMs,
    this.elapsedBeforeMs = 0,
    Map<String, int>? extraMin,
    Map<String, int>? actualSec,
    Set<String>? skipped,
    this.finished = false,
  })  : extraMin = extraMin ?? {},
        actualSec = actualSec ?? {},
        skipped = skipped ?? {};

  int index;

  /// Момент запуска текущего отрезка; null — пауза.
  int? startedAtMs;

  /// Сколько прошло в текущем блоке до последней паузы.
  int elapsedBeforeMs;

  /// Изменение длительности блока во время занятия (+1/−1 мин).
  final Map<String, int> extraMin;

  /// Фактическое время по блокам, секунды.
  final Map<String, int> actualSec;
  final Set<String> skipped;
  bool finished;

  bool get running => startedAtMs != null;

  Duration elapsed(DateTime now) =>
      Duration(milliseconds: elapsedBeforeMs + (startedAtMs == null ? 0 : now.millisecondsSinceEpoch - startedAtMs!));

  Duration planned(TrainingBlock b) => Duration(minutes: (b.durationMin + (extraMin[b.id] ?? 0)).clamp(1, 600));

  /// Остаток времени блока; отрицательный — блок идёт дольше плана.
  Duration remaining(TrainingBlock b, DateTime now) => planned(b) - elapsed(now);

  void start(DateTime now) => startedAtMs ??= now.millisecondsSinceEpoch;

  void pause(DateTime now) {
    if (startedAtMs == null) return;
    elapsedBeforeMs += now.millisecondsSinceEpoch - startedAtMs!;
    startedAtMs = null;
  }

  void adjust(TrainingBlock b, int minutes) {
    final next = (extraMin[b.id] ?? 0) + minutes;
    if (b.durationMin + next < 1) return;
    extraMin[b.id] = next;
  }

  /// Завершить текущий блок и перейти к следующему. Возвращает true, если занятие закончено.
  bool next(List<TrainingBlock> blocks, DateTime now, {bool skip = false}) {
    final b = blocks[index];
    final wasRunning = running;
    if (skip) skipped.add(b.id);
    actualSec[b.id] = elapsed(now).inSeconds;
    elapsedBeforeMs = 0;
    startedAtMs = wasRunning ? now.millisecondsSinceEpoch : null;
    if (index >= blocks.length - 1) {
      startedAtMs = null;
      finished = true;
      return true;
    }
    index++;
    return false;
  }

  /// Вернуться к предыдущему блоку (если нажали «Далее» по ошибке): время блока продолжается.
  void back(List<TrainingBlock> blocks, DateTime now) {
    if (index == 0) return;
    final wasRunning = running;
    index--;
    final id = blocks[index].id;
    elapsedBeforeMs = (actualSec.remove(id) ?? 0) * 1000;
    skipped.remove(id);
    startedAtMs = wasRunning ? now.millisecondsSinceEpoch : null;
  }

  /// Сводка для сохранения в TrainingSession.actual.
  Json toActual() => {
        'blocks': actualSec,
        'skipped': skipped.toList(),
        'extra_min': extraMin,
      };

  String encode() => jsonEncode({
        'index': index,
        'started_at_ms': startedAtMs,
        'elapsed_before_ms': elapsedBeforeMs,
        'extra_min': extraMin,
        'actual_sec': actualSec,
        'skipped': skipped.toList(),
        'finished': finished,
      });

  factory RunState.decode(String s) {
    final j = jsonDecode(s) as Json;
    return RunState(
      index: j['index'] as int,
      startedAtMs: j['started_at_ms'] as int?,
      elapsedBeforeMs: j['elapsed_before_ms'] as int,
      extraMin: (j['extra_min'] as Json).map((k, v) => MapEntry(k, v as int)),
      actualSec: (j['actual_sec'] as Json).map((k, v) => MapEntry(k, v as int)),
      skipped: (j['skipped'] as List).cast<String>().toSet(),
      finished: j['finished'] as bool,
    );
  }
}

String formatClock(Duration d) {
  final neg = d.isNegative;
  final s = d.inSeconds.abs();
  final text = '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  return neg ? '+$text' : text;
}
