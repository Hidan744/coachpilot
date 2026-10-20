import '../data/models.dart';

/// Расстановки по форматам игры: число полевых по линиям от обороны к атаке.
const formations = <String, List<String>>{
  '11×11': ['4-4-2', '4-3-3', '4-2-3-1', '4-1-4-1', '3-5-2', '3-4-3', '5-3-2'],
  '8×8': ['3-3-1', '3-2-2', '2-3-2'],
  '7×7': ['2-3-1', '3-2-1', '2-1-2-1'],
  '6×6': ['2-2-1', '2-1-2'],
  '5×5': ['2-2', '1-2-1'],
};

List<int> formationLines(String f) => f.split('-').map(int.parse).toList();

/// Точки расстановки на вертикальном поле (свои ворота снизу), первая — вратарь.
/// [opponent] — зеркально, сверху.
List<Offset2> formationPoints(String f, {bool opponent = false}) {
  final lines = formationLines(f);
  const gkY = 0.93, backY = 0.78, frontY = 0.56;
  final pts = <Offset2>[const Offset2(0.5, gkY)];
  for (var li = 0; li < lines.length; li++) {
    final y = lines.length == 1 ? backY : backY - (backY - frontY) * li / (lines.length - 1);
    final n = lines[li];
    // Крайние игроки линии ближе к бровкам, если в линии много игроков.
    final spread = n >= 4 ? 0.8 : (n == 3 ? 0.62 : (n == 2 ? 0.44 : 0.0));
    for (var i = 0; i < n; i++) {
      final x = n == 1 ? 0.5 : 0.5 - spread / 2 + spread * i / (n - 1);
      pts.add(Offset2(x, y));
    }
  }
  return opponent ? [for (final p in pts) Offset2(1 - p.x, 1 - p.y)] : pts;
}

int playersInFormation(String f) => formationLines(f).fold(1, (a, b) => a + b);

/// Подпись фишки: «номер|Фамилия».
String tokenLabel(Player p) {
  final num = p.number?.toString() ?? (p.lastName.isNotEmpty ? p.lastName[0] : p.firstName[0]).toUpperCase();
  final name = p.lastName.isNotEmpty ? p.lastName : p.firstName;
  return '$num|$name';
}

/// Расставить игроков по позициям: вратарь — в ворота, защитники — в первую линию,
/// нападающие — в последнюю; кого не хватило по позиции — на свободные места по порядку.
List<Player?> assignLineup(String f, List<Player> players) {
  final lines = formationLines(f);
  final slots = <String>['GK'];
  for (var li = 0; li < lines.length; li++) {
    final pos = li == 0 ? 'DF' : (li == lines.length - 1 && lines.length > 1 ? 'FW' : 'MF');
    slots.addAll(List.filled(lines[li], pos));
  }
  final out = List<Player?>.filled(slots.length, null);
  final pool = [...players];
  for (var i = 0; i < slots.length; i++) {
    final k = pool.indexWhere((p) => p.position == slots[i]);
    if (k >= 0) out[i] = pool.removeAt(k);
  }
  // Вратарь — только вратарь, если он есть в заявке; полевые места добираем остальными.
  for (var i = 1; i < slots.length; i++) {
    if (out[i] != null) continue;
    final k = pool.indexWhere((p) => p.position != 'GK');
    if (k >= 0) out[i] = pool.removeAt(k);
  }
  if (out[0] == null && pool.isNotEmpty) out[0] = pool.removeAt(0);
  return out;
}

/// Элементы доски для расстановки: свои фишки красные (вратарь — тёмный), соперник — белые.
List<SchemeItem> formationItems(String f, {List<Player?> lineup = const [], bool opponent = false}) {
  final pts = formationPoints(f, opponent: opponent);
  return [
    for (var i = 0; i < pts.length; i++)
      SchemeItem(
        type: i == 0 ? (opponent ? 'player_b' : 'goalkeeper') : (opponent ? 'player_b' : 'player_a'),
        x: pts[i].x,
        y: pts[i].y,
        label: i < lineup.length && lineup[i] != null ? tokenLabel(lineup[i]!) : (opponent ? null : '${i + 1}'),
      ),
  ];
}

/// Свои игроки на доске: красные фишки и свой вратарь.
bool isOwnToken(SchemeItem it) => it.type == 'player_a' || it.type == 'goalkeeper';

/// Поворот доски: вертикальное поле (атака вверх) ↔ горизонтальное (атака вправо).
Scheme rotateBoard(Scheme s) {
  final toH = s.field == 'full_v';
  Offset2 map(double x, double y) => toH ? Offset2(1 - y, x) : Offset2(y, 1 - x);
  SchemeItem conv(SchemeItem it) {
    final a = map(it.x, it.y);
    final b = it.x2 == null ? null : map(it.x2!, it.y2!);
    return SchemeItem(
      type: it.type,
      x: a.x,
      y: a.y,
      x2: b?.x,
      y2: b?.y,
      label: it.label,
      step: it.step,
      points: it.points?.map((p) => map(p.x, p.y)).toList(),
      color: it.color,
    );
  }

  return Scheme(field: toH ? 'full' : 'full_v', items: s.items.map(conv).toList());
}

/// Упростить линию от руки: точки ближе [minDist] друг к другу выбрасываются, не больше [maxPoints].
List<Offset2> simplifyStroke(List<Offset2> pts, {double minDist = 0.006, int maxPoints = 400}) {
  if (pts.length < 3) return pts;
  final out = <Offset2>[pts.first];
  for (final p in pts.skip(1)) {
    final last = out.last;
    final dx = p.x - last.x, dy = p.y - last.y;
    if (dx * dx + dy * dy >= minDist * minDist) out.add(p);
  }
  if (out.last != pts.last) out.add(pts.last);
  while (out.length > maxPoints) {
    final thinned = <Offset2>[for (var i = 0; i < out.length; i += 2) out[i]];
    if (thinned.last != out.last) thinned.add(out.last);
    out
      ..clear()
      ..addAll(thinned);
  }
  return out;
}
