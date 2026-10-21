import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/lineup.dart';
import '../../../core/performance.dart';
import '../../../core/providers.dart';
import '../../../core/tactics.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/team_switcher.dart';
import '../calendar/calendar_screen.dart';
import '../sessions/sessions_screens.dart';
import '../team/performance_providers.dart';
import '../team/team_screens.dart';

/// Данные для подбора состава команды: статистика сезона и готовность игроков.
/// [key] — команда и матч, который не учитывать (идущий в Live матч не должен считаться «прошлой нагрузкой»).
final lineupDataProvider =
    Provider.family<(List<Player>, Map<String, SeasonStats>, Map<String, Readiness>)?, (String, String?)>((ref, key) {
  final (teamId, skipMatch) = key;
  final players = ref.watch(playersProvider(teamId)).value;
  final matches = ref.watch(matchesProvider).value;
  final stats = ref.watch(matchStatsProvider).value;
  final attendance = ref.watch(allAttendanceProvider).value;
  final sessions = ref.watch(sessionsProvider).value;
  if (players == null || matches == null || stats == null || attendance == null || sessions == null) return null;
  final mine = [for (final m in matches) if (m.teamId == teamId && m.id != skipMatch) m];
  final ids = {for (final m in mine) m.id};
  final rows = [for (final s in stats) if (ids.contains(s.matchId)) s];
  final active = [for (final p in players) if (p.active) p];
  final ready = teamReadiness(
    players: active,
    matches: mine,
    stats: rows,
    attendance: attendance,
    sessions: {for (final s in sessions) s.id: s},
    now: DateTime.now(),
  );
  return (active, seasonStats(rows), ready);
});

/// Цвет оценки: 50 — средний игрок команды на этой позиции.
Color scoreColor(int s) => s >= 65 ? AppColors.good : (s >= 45 ? AppColors.warn : AppColors.red);

String shortName(Player p) => p.lastName.isEmpty ? p.firstName : '${p.lastName} ${p.firstName.characters.first}.';

/// Подбор состава под схему и стиль игры: кто на какое место и почему.
class LineupScreen extends ConsumerStatefulWidget {
  const LineupScreen({super.key, this.formation});

  final String? formation;

  @override
  ConsumerState<LineupScreen> createState() => _LineupScreenState();
}

class _LineupScreenState extends ConsumerState<LineupScreen> {
  String? _formation;
  String _style = 'press';
  int _selected = 0;
  final _locked = <int, String>{};

  void _reset(VoidCallback change) => setState(() {
        change();
        _locked.clear();
        _selected = 0;
      });

  Future<void> _toBoard(Team team, Lineup l) async {
    final style = playStyles[l.style]!.$1;
    final notes = [
      'Состав подобран под схему ${l.formation}, стиль: $style. Сила состава ${l.strength}/100.',
      for (final p in l.picks)
        if (p.player != null)
          '${p.role.label}: ${shortName(p.player!)} — ${p.fit!.score}${p.fit!.reasons.isEmpty ? '' : ' (${p.fit!.reasons.first})'}',
    ].join('\n');
    final board = TacticBoard(
      id: newId(),
      teamId: team.id,
      title: 'Состав ${l.formation} · $style',
      formation: l.formation,
      scheme: Scheme(field: 'full_v', items: formationItems(l.formation, lineup: l.players)),
      notes: notes,
    );
    await ref.read(repoProvider).put(Entities.boards, board);
    if (mounted) context.push('/tactics/${board.id}');
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(currentTeamProvider);
    if (team == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Состав под тактику')),
        body: const EmptyState(icon: Icons.groups_outlined, title: 'Нет команды', text: 'Создайте команду и добавьте игроков.'),
      );
    }
    final options = formationsFor(team.defaultPlayers);
    final formation = _formation != null && options.contains(_formation) ? _formation! : (widget.formation != null && options.contains(widget.formation) ? widget.formation! : (options.contains(team.formation) ? team.formation : options[options.length > 1 ? 1 : 0]));
    final data = ref.watch(lineupDataProvider((team.id, null)));
    return Scaffold(
      appBar: AppBar(title: const Text('Состав под тактику')),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : _body(team, formation, options, data),
    );
  }

  Widget _body(Team team, String formation, List<String> options, (List<Player>, Map<String, SeasonStats>, Map<String, Readiness>) data) {
    final (players, season, ready) = data;
    if (players.length < playersInFormation(formation)) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const TeamSwitcher(padding: EdgeInsets.only(bottom: 8)),
        EmptyState(
          icon: Icons.groups_outlined,
          title: 'Мало игроков',
          text: 'Для схемы $formation нужно ${playersInFormation(formation)} игроков, в команде ${players.length}. '
              'Добавьте игроков в разделе «Команда».',
        ),
      ]);
    }
    final l = suggestLineup(formation: formation, style: _style, players: players, season: season, ready: ready, locked: _locked);
    final sel = l.picks[_selected.clamp(0, l.picks.length - 1)];
    final t = Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 120), children: [
      const TeamSwitcher(padding: EdgeInsets.only(bottom: 8)),
      Text('Схема', style: t.textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in options)
          ChoiceChip(label: Text(f), selected: f == formation, onSelected: (_) => _reset(() => _formation = f)),
      ]),
      const SizedBox(height: 12),
      Text('Стиль игры', style: t.textTheme.labelLarge),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: [for (final e in playStyles.entries) ButtonSegment(value: e.key, label: Text(e.value.$1))],
        selected: {_style},
        onSelectionChanged: (s) => _reset(() => _style = s.first),
      ),
      const SizedBox(height: 4),
      Text(playStyles[_style]!.$2, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Сила состава: ${l.strength} из 100',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scoreColor(l.strength))),
            const Text('50 — средний игрок команды на этой позиции',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ),
        FilledButton.icon(
          onPressed: () => _toBoard(team, l),
          icon: const Icon(Icons.draw_outlined),
          label: const Text('На тактическую доску'),
        ),
      ]),
      const SizedBox(height: 10),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: AspectRatio(
            aspectRatio: 0.7,
            child: LineupPitch(lineup: l, selected: _selected, onTap: (i) => setState(() => _selected = i)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      _PickCard(
        pick: sel,
        onReplace: (p) => setState(() {
          _locked.removeWhere((_, id) => id == p.id);
          _locked[_selected] = p.id;
        }),
      ),
      if (l.bench.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Скамейка', style: t.textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final (p, role, fit) in l.bench)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 16, child: Text(p.number?.toString() ?? '—', style: const TextStyle(fontSize: 12))),
            title: Text(p.fullName),
            subtitle: Text('Лучше всего: ${role.label.toLowerCase()}'
                '${fit.warnings.isEmpty ? '' : ' · ${fit.warnings.first}'}'),
            trailing: _ScoreBadge(fit.score),
            onTap: () => context.push('/team/player/${p.id}'),
          ),
      ],
      if (l.unavailable.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Не могут играть', style: t.textTheme.titleMedium),
        for (final (p, why) in l.unavailable)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.healing_outlined, color: AppColors.red),
            title: Text(p.fullName),
            subtitle: Text(why),
          ),
      ],
      const SizedBox(height: 12),
      const Text(
        'Как считается: для каждой позиции в схеме свои главные показатели (у опорного — перехваты и подборы, '
        'у нападающего — голы и удары), стиль игры добавляет свои требования. Игрок сравнивается с командой за 90 минут '
        'игры. Учитываются форма, нагрузка за неделю, пропуски тренировок; травмированные и дисквалифицированные не попадают в состав. '
        'Решение остаётся за тренером: нажмите на игрока и выберите замену.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
    ]);
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge(this.score);

  final int score;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scoreColor(score).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scoreColor(score).withValues(alpha: 0.7)),
        ),
        child: Text('$score', style: TextStyle(color: scoreColor(score), fontWeight: FontWeight.w700)),
      );
}

/// Выбранное место: роль, игрок, почему он, и кем можно заменить.
class _PickCard extends StatelessWidget {
  const _PickCard({required this.pick, required this.onReplace});

  final LineupPick pick;
  final ValueChanged<Player> onReplace;

  @override
  Widget build(BuildContext context) {
    final p = pick.player, fit = pick.fit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pick.role.label.toUpperCase(),
              style: const TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Text(p == null ? 'Нет игрока' : '${p.number == null ? '' : '${p.number} · '}${p.fullName}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            if (fit != null) _ScoreBadge(fit.score),
          ]),
          if (fit != null) ...[
            const SizedBox(height: 6),
            for (final r in fit.reasons)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_outline, size: 16, color: AppColors.good),
                  const SizedBox(width: 6),
                  Expanded(child: Text(r)),
                ]),
              ),
            for (final w in fit.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warn),
                  const SizedBox(width: 6),
                  Expanded(child: Text(w)),
                ]),
              ),
          ],
          if (pick.alternatives.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Замена со скамейки:', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (b, f) in pick.alternatives)
                ActionChip(
                  avatar: const Icon(Icons.swap_vert, size: 18),
                  label: Text('${shortName(b)} · ${f.score}'),
                  onPressed: () => onReplace(b),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Поле с составом: фишки на местах схемы, цвет — оценка игрока на этом месте.
class LineupPitch extends StatelessWidget {
  const LineupPitch({super.key, required this.lineup, required this.selected, required this.onTap});

  final Lineup lineup;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    // На доске расстановка занимает свою половину поля, здесь — всё поле: вратарь внизу, атака у чужой штрафной.
    final pts = [
      for (final p in formationPoints(lineup.formation)) Offset2(p.x, 0.92 - (0.93 - p.y) / 0.37 * 0.7),
    ];
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
          for (var i = 0; i < pts.length && i < lineup.picks.length; i++)
            Positioned(
              left: pts[i].x * w - 46,
              top: pts[i].y * h - 24,
              width: 92,
              child: _Token(pick: lineup.picks[i], selected: i == selected, onTap: () => onTap(i)),
            ),
        ]),
      );
    });
  }
}

class _Token extends StatelessWidget {
  const _Token({required this.pick, required this.selected, required this.onTap});

  final LineupPick pick;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = pick.player;
    final score = pick.fit?.score ?? 0;
    final c = scoreColor(score);
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: pick.role.line == 'GK' ? const Color(0xFF26262A) : AppColors.red,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? Colors.white : c, width: selected ? 3 : 2.5),
            boxShadow: [if (selected) BoxShadow(color: Colors.white.withValues(alpha: 0.5), blurRadius: 12)],
          ),
          child: Text(p?.number?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
          child: Text(
            p == null ? pick.role.label : '${p.lastName.isEmpty ? p.firstName : p.lastName} $score',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p == null ? AppColors.textMuted : Colors.white),
          ),
        ),
      ]),
    );
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF14361F), Color(0xFF0E2817)],
          ).createShader(r));
    final stripe = Paint()..color = Colors.white.withValues(alpha: 0.025);
    for (var i = 0; i < 10; i += 2) {
      canvas.drawRect(Rect.fromLTWH(0, s.height * i / 10, s.width, s.height / 10), stripe);
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final m = 10.0;
    canvas.drawRect(Rect.fromLTRB(m, m, s.width - m, s.height - m), line);
    canvas.drawLine(Offset(m, s.height / 2), Offset(s.width - m, s.height / 2), line);
    canvas.drawCircle(Offset(s.width / 2, s.height / 2), s.width * 0.13, line);
    final bw = s.width * 0.5, bh = s.height * 0.13;
    canvas.drawRect(Rect.fromLTWH((s.width - bw) / 2, m, bw, bh), line);
    canvas.drawRect(Rect.fromLTWH((s.width - bw) / 2, s.height - m - bh, bw, bh), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Вход в подбор состава: карточка над списком досок.
class LineupEntryCard extends StatelessWidget {
  const LineupEntryCard({super.key});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/tactics/lineup'),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3A0A0D), Color(0xFF151517)])),
            child: const Row(children: [
              Icon(Icons.groups_2_outlined, color: AppColors.red, size: 32),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Подобрать состав под тактику', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  SizedBox(height: 2),
                  Text('Выберите схему и стиль игры — приложение предложит игрока на каждое место и объяснит почему',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ]),
              ),
              Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );
}
