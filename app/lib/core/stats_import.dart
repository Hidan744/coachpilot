// Импорт статистики матча из таблицы (Excel, Word, CSV): строка — игрок, колонки — показатели.

import '../data/models.dart';
import 'performance.dart';

class ImportedStat {
  ImportedStat(this.player, {this.minutes = 0, this.started = false, this.rating, this.stats = const {}});

  final Player player;
  final int minutes;
  final bool started;
  final double? rating;
  final Map<String, double> stats;
}

/// Названия колонок → показатель. Сравнение по началу слова, без регистра.
const _columns = <String, List<String>>{
  'minutes': ['мин', 'minutes', 'время на поле'],
  'started': ['старт', 'в старте', 'основа'],
  'rating': ['оценк', 'рейтинг', 'rating'],
  'goals': ['гол', 'голы', 'забит', 'goals'],
  'assists': ['ассист', 'голевые пер', 'гол. пер', 'голевая', 'assists'],
  'shots_on': ['удары в створ', 'в створ', 'удар в створ'],
  'shots': ['удары', 'удар', 'shots'],
  'passes_ok': ['точные пер', 'точн'],
  'passes': ['передачи', 'пасы', 'passes'],
  'key_passes': ['ключев'],
  'dribbles': ['обвод', 'дриблинг'],
  'tackles': ['отбор'],
  'interceptions': ['перехват'],
  'duels_won': ['единоборств'],
  'fouls': ['фол'],
  'yellow': ['жк', 'желт', 'жёлт'],
  'red': ['кк', 'красн'],
  'saves': ['сейв', 'спас'],
  'conceded': ['пропущ'],
};

String _norm(String s) => s.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ').trim();

String? _columnKey(String header) {
  final h = _norm(header);
  if (h.isEmpty) return null;
  // Сначала более длинные варианты: «удары в створ» раньше «удары», «голевые передачи» раньше «гол».
  final pairs = [
    for (final e in _columns.entries)
      for (final v in e.value) (e.key, _norm(v)),
  ]..sort((a, b) => b.$2.length.compareTo(a.$2.length));
  for (final (key, v) in pairs) {
    if (h == v || h.startsWith(v) || (v.length >= 5 && h.contains(v))) return key;
  }
  return null;
}

/// Игрок команды по имени или номеру из ячеек строки.
Player? _findPlayer(List<String> cells, List<Player> players) {
  for (final c in cells) {
    final t = _norm(c);
    if (t.isEmpty) continue;
    for (final p in players) {
      final last = _norm(p.lastName), first = _norm(p.firstName);
      if (last.isNotEmpty && (t == last || t.startsWith('$last ') || t.endsWith(' $last') || t.contains(' $last '))) return p;
      if (last.isEmpty && t.contains(first)) return p;
      if (t == _norm(p.fullName) || t == '$last $first') return p;
    }
  }
  return null;
}

List<ImportedStat> parseStatsTable(List<List<String>> rows, List<Player> players) {
  Map<int, String>? header;
  final out = <String, ImportedStat>{};
  for (final row in rows) {
    final mapped = <int, String>{};
    for (var i = 0; i < row.length; i++) {
      final k = _columnKey(row[i]);
      if (k != null) mapped[i] = k;
    }
    // Строка заголовка: хотя бы два узнанных показателя и нет игрока.
    if (mapped.length >= 2 && _findPlayer(row, players) == null) {
      header = mapped;
      continue;
    }
    if (header == null) continue;
    final player = _findPlayer(row, players);
    if (player == null) continue;
    var minutes = 0;
    var started = false;
    double? rating;
    final stats = <String, double>{};
    for (final e in header.entries) {
      if (e.key >= row.length) continue;
      final raw = row[e.key].trim();
      if (e.value == 'started') {
        started = RegExp(r'^(да|\+|1|x|х|yes|в старте)$', caseSensitive: false).hasMatch(raw);
        continue;
      }
      final v = double.tryParse(raw.replaceAll(',', '.').replaceAll('%', ''));
      if (v == null || v < 0) continue;
      switch (e.value) {
        case 'minutes':
          minutes = v.round().clamp(0, 150);
        case 'rating':
          rating = v >= 1 && v <= 10 ? v : null;
        default:
          if (v > 0) stats[e.value] = v;
      }
    }
    if (minutes == 0 && (stats.isNotEmpty || rating != null)) minutes = 90;
    out[player.id] = ImportedStat(player, minutes: minutes, started: started || minutes >= 60, rating: rating, stats: stats);
  }
  return out.values.toList();
}

/// Подписи показателей для заголовка шаблона.
List<String> statsTemplateHeader() => ['Игрок', 'Минуты', 'В старте', 'Оценка', for (final k in statKeys) k.label];
