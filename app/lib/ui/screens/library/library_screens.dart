import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/plan_rules.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../sessions/sessions_screens.dart';
import '../../widgets/scheme_view.dart';
import 'import_drills_screen.dart';
import 'scheme_editor.dart';

final drillsProvider = StreamProvider<List<Drill>>((ref) => ref.watch(repoProvider).watchDrills().map((l) {
      final order = DrillCategories.all.keys.toList();
      return l
        ..sort((a, b) {
          final c = order.indexOf(a.category).compareTo(order.indexOf(b.category));
          return c != 0 ? c : a.title.compareTo(b.title);
        });
    }));

final favoritesProvider = StreamProvider<Set<String>>((ref) => ref.watch(repoProvider).watchFavoriteDrillIds());

final drillProvider = Provider.family<Drill?, String>(
  (ref, id) => (ref.watch(drillsProvider).value ?? const []).where((d) => d.id == id).firstOrNull,
);

class DrillFilter {
  const DrillFilter({
    this.query = '',
    this.category,
    this.tab = 'all',
    this.fitTeam = false,
    this.audience,
    this.intensities = const {},
    this.maxDuration,
    this.players,
    this.age,
    this.equipment,
  });

  final String query;
  final String? category;
  final String tab; // all | favorites | mine
  final bool fitTeam;

  /// Раздел: kids — детско-юношеский футбол, adults — взрослые; null — по выбранной команде.
  final String? audience;

  /// Подробные фильтры: интенсивность, длительность до N мин, подходит для N игроков,
  /// возраст N лет, только с этим инвентарём (null — любой).
  final Set<String> intensities;
  final int? maxDuration, players, age;
  final Set<String>? equipment;

  /// Сколько подробных фильтров включено — для значка на кнопке.
  int get extraCount =>
      (intensities.isEmpty ? 0 : 1) + (maxDuration == null ? 0 : 1) + (players == null ? 0 : 1) + (age == null ? 0 : 1) + (equipment == null ? 0 : 1);

  DrillFilter copyWith({String? query, String? Function()? category, String? tab, bool? fitTeam, String? audience}) => DrillFilter(
        query: query ?? this.query,
        category: category == null ? this.category : category(),
        tab: tab ?? this.tab,
        fitTeam: fitTeam ?? this.fitTeam,
        audience: audience ?? this.audience,
        intensities: intensities,
        maxDuration: maxDuration,
        players: players,
        age: age,
        equipment: equipment,
      );

  DrillFilter withExtra({Set<String>? intensities, int? maxDuration, int? players, int? age, Set<String>? equipment}) => DrillFilter(
        query: query,
        category: category,
        tab: tab,
        fitTeam: fitTeam,
        audience: audience,
        intensities: intensities ?? const {},
        maxDuration: maxDuration,
        players: players,
        age: age,
        equipment: equipment,
      );
}

/// Раздел библиотеки: выбранный вручную или по команде (взрослая команда → «Взрослые»).
final audienceProvider = Provider<String>((ref) {
  final chosen = ref.watch(drillFilterProvider).audience;
  if (chosen != null) return chosen;
  return ref.watch(currentTeamProvider)?.ageGroup == 'adult' ? 'adults' : 'kids';
});

/// Подходит ли упражнение разделу: детям — с подходящим возрастом, взрослым — без верхней границы.
bool drillForAudience(Drill d, String audience) => audience == 'adults' ? d.ageMax >= 18 : d.ageMin < 18;

class DrillFilterController extends Notifier<DrillFilter> {
  @override
  DrillFilter build() => const DrillFilter();

  void update(DrillFilter Function(DrillFilter) f) => state = f(state);
}

final drillFilterProvider = NotifierProvider<DrillFilterController, DrillFilter>(DrillFilterController.new);

/// Подходит ли упражнение команде: возраст, число игроков, инвентарь.
bool drillFitsTeam(Drill d, Team t, {int? players}) {
  final age = AgeGroups.age(t.ageGroup);
  final n = players ?? t.defaultPlayers;
  return age >= d.ageMin &&
      age <= d.ageMax &&
      n >= d.playersMin &&
      d.equipment.every((e) => t.equipment.contains(e) || e == 'balls' || e == 'cones');
}

List<Drill> applyFilter(List<Drill> all, DrillFilter f, Set<String> favs, Team? team, {String? audience}) {
  final q = f.query.trim().toLowerCase();
  return all.where((d) {
    if (audience != null && !drillForAudience(d, audience)) return false;
    if (f.tab == 'favorites' && !favs.contains(d.id)) return false;
    if (f.tab == 'mine' && d.isSystem) return false;
    if (f.category != null && d.category != f.category) return false;
    if (f.fitTeam && team != null && !drillFitsTeam(d, team)) return false;
    if (f.intensities.isNotEmpty && !f.intensities.contains(d.intensity)) return false;
    if (f.maxDuration != null && d.durationMin > f.maxDuration!) return false;
    if (f.players != null && (f.players! < d.playersMin || f.players! > d.playersMax)) return false;
    if (f.age != null && (f.age! < d.ageMin || f.age! > d.ageMax)) return false;
    if (f.equipment != null && !d.equipment.every((e) => f.equipment!.contains(e))) return false;
    // Поиск — по названию, цели, тегам, организации и шагам выполнения.
    if (q.isNotEmpty &&
        !('${d.title} ${d.goal} ${d.tags.join(' ')} ${d.setup} ${d.steps.join(' ')}').toLowerCase().contains(q)) {
      return false;
    }
    return true;
  }).toList();
}

/// Кратко об упражнении; для взрослых — без возраста.
String drillMeta(Drill d, {bool adults = false}) => [
      '${d.durationMin} мин',
      d.playersMax >= 30 ? 'от ${d.playersMin} игр.' : '${d.playersMin}–${d.playersMax} игр.',
      if (!adults) d.ageMax >= 99 ? 'от ${d.ageMin} лет' : '${d.ageMin}–${d.ageMax} лет',
    ].join(' · ');

const _intensityLabel = {'low': 'низкая', 'medium': 'средняя', 'high': 'высокая'};

/// Рекомендации для детей по возрастам: сколько минут, с какой интенсивностью и как дозировать.
List<(String, String, String, String)> kidsDosage(Drill d) {
  final hi = d.intensity == 'high';
  final rows = <(String, String, String, String)>[];
  void add(int from, int to, String age, double timeK, String intensity, String how) {
    if (d.ageMin > to || d.ageMax < from) return;
    rows.add((age, '${(d.durationMin * timeK).round().clamp(5, 60)} мин', intensity, how));
  }

  add(6, 8, '6–8 лет', 0.6, hi ? 'средняя' : _intensityLabel[d.intensity]!, 'Игровая форма, отрезки по 2–3 мин с паузой, много касаний мяча');
  add(9, 11, '9–11 лет', 0.8, hi ? 'средняя → высокая' : _intensityLabel[d.intensity]!,
      'Серии по 3–4 мин, пауза 1 мин; акцент на технику и решения');
  add(12, 14, '12–14 лет', 1, _intensityLabel[d.intensity]!,
      hi ? 'Работа : отдых 1 : 1, следить за усталостью в период роста' : 'Полный объём, усложнять правила');
  add(15, 17, '15–17 лет', 1, _intensityLabel[d.intensity]!, hi ? 'Работа : отдых 2 : 1, как у взрослых' : 'Полный объём с соревновательным элементом');
  return rows;
}

/// Рекомендации для взрослых: интенсивность и как дозировать.
String adultsDosage(Drill d) => switch (d.intensity) {
      'high' => 'Высокая интенсивность: ${d.durationMin} мин, серии 3–4 мин, отдых 1–2 мин. Не ставить за день до игры.',
      'low' => 'Низкая интенсивность: ${d.durationMin} мин. Подходит для восстановления и дня перед игрой.',
      _ => 'Средняя интенсивность: ${d.durationMin} мин, серии 4–6 мин, отдых 1 мин.',
    };

const categoryIcons = {
  'warmup': Icons.directions_run,
  'technique': Icons.sports_soccer,
  'passing': Icons.swap_horiz,
  'dribbling': Icons.gesture,
  'finishing': Icons.sports_score,
  'possession': Icons.hub_outlined,
  'tactics': Icons.account_tree_outlined,
  'transition': Icons.sync_alt,
  'defending': Icons.shield_outlined,
  'physical': Icons.fitness_center,
  'game': Icons.stadium_outlined,
  'cooldown': Icons.self_improvement,
  'goalkeeping': Icons.sports_handball,
};

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, this.pickMode = false});

  /// Режим выбора упражнения для плана: возвращает Drill через pop.
  final bool pickMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(drillFilterProvider);
    final ctrl = ref.read(drillFilterProvider.notifier);
    final favs = ref.watch(favoritesProvider).value ?? const {};
    final team = ref.watch(currentTeamProvider);
    final drills = ref.watch(drillsProvider);
    final audience = ref.watch(audienceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(pickMode ? 'Выбор упражнения' : 'Библиотека'),
        actions: [
          if (!pickMode)
            IconButton(
              tooltip: 'Импорт упражнений из файла',
              icon: const Icon(Icons.upload_file),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportDrillsScreen())),
            ),
          if (!pickMode) const SyncBadge(),
        ],
      ),
      floatingActionButton: pickMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/library/edit/new'),
              icon: const Icon(Icons.add),
              label: const Text('Своё упражнение'),
            ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Поиск',
              hintText: 'рондо, удар, 1×1…',
            ),
            onChanged: (v) => ctrl.update((s) => s.copyWith(query: v)),
          ),
        ),
        // Разделы библиотеки: детский и взрослый футбол.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'kids', icon: Icon(Icons.child_care), label: Text('Дети и юноши')),
              ButtonSegment(value: 'adults', icon: Icon(Icons.person), label: Text('Взрослые')),
            ],
            selected: {audience},
            onSelectionChanged: (s) => ctrl.update((x) => x.copyWith(audience: s.first)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('Все')),
              ButtonSegment(value: 'favorites', label: Text('Избранное')),
              ButtonSegment(value: 'mine', label: Text('Мои')),
            ],
            selected: {f.tab},
            onSelectionChanged: (s) => ctrl.update((x) => x.copyWith(tab: s.first)),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  avatar: const Icon(Icons.tune, size: 18),
                  label: Text(f.extraCount == 0 ? 'Фильтры' : 'Фильтры · ${f.extraCount}'),
                  selected: f.extraCount > 0,
                  onSelected: (_) => showDrillFiltersSheet(context, ref),
                ),
              ),
              if (team != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: const Icon(Icons.groups_outlined, size: 18),
                    label: Text('Под ${team.name}'),
                    selected: f.fitTeam,
                    onSelected: (v) => ctrl.update((s) => s.copyWith(fitTeam: v)),
                  ),
                ),
              for (final e in DrillCategories.all.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: f.category == e.key,
                    onSelected: (v) => ctrl.update((s) => s.copyWith(category: () => v ? e.key : null)),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView(drills, builder: (all) {
            final list = applyFilter(all, f, favs, team, audience: audience);
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.search_off,
                title: f.tab == 'mine'
                    ? 'Своих упражнений пока нет'
                    : f.tab == 'favorites'
                        ? 'В избранном пусто'
                        : 'Ничего не найдено',
                text: f.tab == 'mine'
                    ? 'Создайте своё, скопируйте упражнение из библиотеки или загрузите свои упражнения файлом.'
                    : null,
                action: f.tab == 'mine'
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Загрузить из Word или Excel'),
                        onPressed: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportDrillsScreen())),
                      )
                    : null,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final d = list[i];
                return ListTile(
                  leading: CircleAvatar(child: Icon(categoryIcons[d.category] ?? Icons.sports_soccer)),
                  title: Text(d.title),
                  subtitle: Text('${DrillCategories.all[d.category]} · ${drillMeta(d, adults: audience == 'adults')}'),
                  trailing: favs.contains(d.id) ? const Icon(Icons.star, color: Colors.amber) : null,
                  onTap: () async {
                    if (pickMode) {
                      Navigator.pop(context, d);
                    } else {
                      context.push('/library/drill/${d.id}');
                    }
                  },
                );
              },
            );
          }),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- карточка упражнения

/// Содержимое карточки упражнения — используется и в библиотеке, и в плане, и в режиме занятия.
/// Упражнение в нижней панели: схема с анимацией и описание.
Future<void> showDrillSheet(BuildContext context, Drill drill) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          Text(drill.title, style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 8),
          DrillDetails(drill),
        ]),
      ),
    );

class DrillDetails extends ConsumerWidget {
  const DrillDetails(this.drill, {super.key, this.compact = false});

  final Drill drill;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final adults = ref.watch(audienceProvider) == 'adults';
    final dosage = adults ? const <(String, String, String, String)>[] : kidsDosage(drill);
    Widget section(String title, List<String> items, {bool numbered = false}) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 24, child: Text(numbered ? '${i + 1}.' : '•', style: t.textTheme.bodyLarge)),
                Expanded(child: Text(items[i], style: t.textTheme.bodyLarge)),
              ]),
            ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (drill.scheme != null && drill.scheme!.items.isNotEmpty) ...[
        SchemeView(drill.scheme!),
        const SizedBox(height: 12),
      ],
      Wrap(spacing: 8, runSpacing: 8, children: [
        Chip(label: Text(DrillCategories.all[drill.category] ?? drill.category)),
        Chip(label: Text(drillMeta(drill, adults: adults))),
        if (drill.fieldSize.isNotEmpty) Chip(label: Text(drill.fieldSize)),
        Chip(label: Text(switch (drill.intensity) { 'low' => 'Низкая интенсивность', 'high' => 'Высокая интенсивность', _ => 'Средняя интенсивность' })),
        if (drill.source == 'ai') const Chip(avatar: Icon(Icons.auto_awesome, size: 16), label: Text('Создано AI — проверьте')),
      ]),
      if (drill.goal.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(drill.goal, style: t.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
      ],
      // Дозировка: детям — по возрастам, взрослым — интенсивность и паузы.
      if (adults)
        section('Рекомендации для взрослых', [adultsDosage(drill)])
      else if (dosage.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Рекомендации по возрасту', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final (age, time, intensity, how) in dosage)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$age · $time · интенсивность: $intensity', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(how, style: const TextStyle(color: AppColors.textMuted)),
                ]),
              ),
          ]),
        ),
      if (drill.equipment.isNotEmpty)
        section('Инвентарь', [drill.equipment.map((e) => Equipment.all[e] ?? e).join(', ')]),
      if (drill.setup.isNotEmpty) section('Организация', [drill.setup]),
      section('Как выполнять', drill.steps, numbered: true),
      section('Правила', drill.rules),
      section('Подсказки тренера', drill.coachingPoints),
      if (!compact) ...[
        section('Критерии успеха', drill.successCriteria),
        section('Упростить', drill.easier),
        section('Усложнить', drill.harder),
      ],
    ]);
  }
}

class DrillScreen extends ConsumerWidget {
  const DrillScreen({super.key, required this.drillId});

  final String drillId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drill = ref.watch(drillProvider(drillId));
    if (drill == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Упражнение не найдено'));
    }
    final fav = (ref.watch(favoritesProvider).value ?? const {}).contains(drill.id);
    final repo = ref.read(repoProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(drill.title),
        actions: [
          IconButton(
            tooltip: fav ? 'Убрать из избранного' : 'В избранное',
            icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
            onPressed: () => repo.setFavorite(drill.id, !fav),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'copy':
                  final copy = Drill.fromJson(newId(), {...drill.toJson(), 'source': 'user', 'title': '${drill.title} (моё)'});
                  await repo.put(Entities.drills, copy);
                  if (context.mounted) context.pushReplacement('/library/edit/${copy.id}');
                case 'edit':
                  context.push('/library/edit/${drill.id}');
                case 'delete':
                  if (await confirm(context, 'Удалить упражнение «${drill.title}»?',
                      text: 'В уже составленных планах оно сохранится.')) {
                    await repo.remove(Entities.drills, drill.id);
                    if (context.mounted) context.pop();
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy', child: Text('Сделать копию и изменить')),
              if (!drill.isSystem) ...const [
                PopupMenuItem(value: 'edit', child: Text('Изменить')),
                PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            icon: const Icon(Icons.playlist_add),
            label: const Text('Добавить в тренировку'),
            onPressed: () => addDrillToPlan(context, ref, drill),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        DrillDetails(drill),
        ...() {
          final similar = similarDrills(drill, ref.watch(drillsProvider).value ?? const []);
          if (similar.isEmpty) return <Widget>[];
          return <Widget>[
            const Divider(height: 32),
            Text('Похожие упражнения', style: Theme.of(context).textTheme.titleMedium),
            for (final x in similar)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Icon(categoryIcons[x.category] ?? Icons.sports_soccer)),
                title: Text(x.title),
                subtitle: Text('${DrillCategories.all[x.category]} · ${drillMeta(x)}'),
                onTap: () => context.pushReplacement('/library/drill/${x.id}'),
              ),
          ];
        }(),
      ]),
    );
  }
}

/// Добавить упражнение в черновик или запланированную тренировку команды, либо создать новую.
Future<void> addDrillToPlan(BuildContext context, WidgetRef ref, Drill d) async {
  final team = ref.read(currentTeamProvider);
  final sessions = [
    for (final s in ref.read(sessionsProvider).value ?? const <TrainingSession>[])
      if ((s.status == 'draft' || s.status == 'planned') && (team == null || s.teamId == team.id)) s,
  ]..sort((a, b) => (a.scheduledAt ?? DateTime(2100)).compareTo(b.scheduledAt ?? DateTime(2100)));
  final target = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (c, scroll) => ListView(controller: scroll, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('«${d.title}» — в какую тренировку?', style: Theme.of(c).textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.add_circle_outline, color: AppColors.red),
          title: const Text('Новая тренировка с этим упражнением'),
          onTap: () => Navigator.pop(c, ''),
        ),
        for (final s in sessions)
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: Text(s.title),
            subtitle: Text('${formatWhen(s.scheduledAt)} · ${SessionStatus.labels[s.status]} · ${s.plannedMinutes} мин'),
            onTap: () => Navigator.pop(c, s.id),
          ),
      ]),
    ),
  );
  if (target == null || !context.mounted) return;
  final repo = ref.read(repoProvider);
  if (target.isEmpty) {
    final s = TrainingSession(
      id: newId(),
      teamId: team?.id,
      title: d.title,
      goal: d.goal.split('.').first,
      durationMin: d.durationMin,
      playersExpected: team?.defaultPlayers,
      equipment: team?.equipment ?? const [],
      blocks: [blockFromDrill(d, id: newId())],
    );
    await repo.put(Entities.sessions, s);
    if (context.mounted) context.push('/sessions/${s.id}');
    return;
  }
  final s = sessions.firstWhere((x) => x.id == target);
  await repo.put(
    Entities.sessions,
    s.copyWith(blocks: [...s.blocks, blockFromDrill(d, id: newId(), intensity: s.params['intensity'] as String? ?? 'medium')]),
  );
  if (context.mounted) showInfo(context, 'Добавлено в «${s.title}»: теперь ${s.plannedMinutes + d.durationMin} мин из ${s.durationMin}');
}

// ---------------------------------------------------------------- редактор упражнения

class DrillEditScreen extends ConsumerStatefulWidget {
  const DrillEditScreen({super.key, this.drillId});

  final String? drillId;

  @override
  ConsumerState<DrillEditScreen> createState() => _DrillEditScreenState();
}

class _DrillEditScreenState extends ConsumerState<DrillEditScreen> {
  final _form = GlobalKey<FormState>();
  late final Drill? _orig = widget.drillId == null ? null : ref.read(drillProvider(widget.drillId!));
  late final _title = TextEditingController(text: _orig?.title);
  late final _goal = TextEditingController(text: _orig?.goal);
  late final _setup = TextEditingController(text: _orig?.setup);
  late final _field = TextEditingController(text: _orig?.fieldSize);
  late final _steps = TextEditingController(text: _orig?.steps.join('\n'));
  late final _rules = TextEditingController(text: _orig?.rules.join('\n'));
  late final _points = TextEditingController(text: _orig?.coachingPoints.join('\n'));
  late final _success = TextEditingController(text: _orig?.successCriteria.join('\n'));
  late final _easier = TextEditingController(text: _orig?.easier.join('\n'));
  late final _harder = TextEditingController(text: _orig?.harder.join('\n'));
  late String _category = _orig?.category ?? 'technique';
  late String _intensity = _orig?.intensity ?? 'medium';
  late RangeValues _ages = RangeValues((_orig?.ageMin ?? 6).toDouble(), (_orig?.ageMax ?? 99).clamp(6, 20).toDouble());
  late RangeValues _players = RangeValues((_orig?.playersMin ?? 2).toDouble(), (_orig?.playersMax ?? 20).clamp(1, 30).toDouble());
  late double _duration = (_orig?.durationMin ?? 10).toDouble().clamp(5, 45);
  late final Set<String> _equipment = {...?_orig?.equipment};
  late Scheme? _scheme = _orig?.scheme;

  List<String> _lines(TextEditingController c) =>
      c.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final d = Drill(
      id: _orig?.id ?? newId(),
      source: 'user',
      title: _title.text.trim(),
      category: _category,
      goal: _goal.text.trim(),
      ageMin: _ages.start.round(),
      ageMax: _ages.end >= 20 ? 99 : _ages.end.round(),
      playersMin: _players.start.round(),
      playersMax: _players.end >= 30 ? 60 : _players.end.round(),
      durationMin: _duration.round(),
      fieldSize: _field.text.trim(),
      intensity: _intensity,
      equipment: _equipment.toList(),
      setup: _setup.text.trim(),
      steps: _lines(_steps),
      rules: _lines(_rules),
      coachingPoints: _lines(_points),
      successCriteria: _lines(_success),
      easier: _lines(_easier),
      harder: _lines(_harder),
      scheme: _scheme,
      tags: _orig?.tags ?? const [],
    );
    await ref.read(repoProvider).put(Entities.drills, d);
    if (_orig == null) ref.read(analyticsProvider).track('drill_created', {'has_scheme': d.scheme != null});
    if (!mounted) return;
    context.pop();
    if (_orig == null) context.push('/library/drill/${d.id}');
  }

  Widget _multiline(TextEditingController c, String label, {String? hint}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextFormField(
          controller: c,
          minLines: 2,
          maxLines: 8,
          decoration: InputDecoration(labelText: label, hintText: hint ?? 'Каждый пункт с новой строки', alignLabelWithHint: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_orig == null ? 'Новое упражнение' : 'Упражнение'),
        actions: [
          TextButton(key: const Key('drill_save'), onPressed: _save, child: const Text('Сохранить')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 48), children: [
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Название'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Введите название' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Категория'),
            items: [for (final e in DrillCategories.all.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _category = v!),
          ),
          _multiline(_goal, 'Цель', hint: 'Что развивает упражнение'),
          const SizedBox(height: 16),
          Text('Схема', style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_scheme != null && _scheme!.items.isNotEmpty) SchemeView(_scheme!),
          OutlinedButton.icon(
            icon: const Icon(Icons.draw_outlined),
            label: Text(_scheme == null || _scheme!.items.isEmpty ? 'Нарисовать схему' : 'Изменить схему'),
            onPressed: () async {
              final s = await Navigator.of(context).push<Scheme>(
                MaterialPageRoute(builder: (_) => SchemeEditorScreen(initial: _scheme)),
              );
              if (s != null) setState(() => _scheme = s);
            },
          ),
          const SizedBox(height: 16),
          Text('Длительность: ${_duration.round()} мин', style: t.textTheme.titleSmall),
          Slider(value: _duration, min: 5, max: 45, divisions: 40, onChanged: (v) => setState(() => _duration = v)),
          Text(
            'Возраст: ${_ages.start.round()}–${_ages.end >= 20 ? 'взрослые' : _ages.end.round()}',
            style: t.textTheme.titleSmall,
          ),
          RangeSlider(values: _ages, min: 6, max: 20, divisions: 14, onChanged: (v) => setState(() => _ages = v)),
          Text(
            'Игроков: ${_players.start.round()}–${_players.end >= 30 ? '30+' : _players.end.round()}',
            style: t.textTheme.titleSmall,
          ),
          RangeSlider(values: _players, min: 1, max: 30, divisions: 29, onChanged: (v) => setState(() => _players = v)),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'low', label: Text('Низкая')),
              ButtonSegment(value: 'medium', label: Text('Средняя')),
              ButtonSegment(value: 'high', label: Text('Высокая')),
            ],
            selected: {_intensity},
            onSelectionChanged: (s) => setState(() => _intensity = s.first),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _field, decoration: const InputDecoration(labelText: 'Размер площадки', hintText: 'Например, 20×20 м')),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in Equipment.all.entries)
              FilterChip(
                label: Text(e.value),
                selected: _equipment.contains(e.key),
                onSelected: (v) => setState(() => v ? _equipment.add(e.key) : _equipment.remove(e.key)),
              ),
          ]),
          _multiline(_setup, 'Организация и расстановка', hint: 'Площадка, расстановка игроков, инвентарь'),
          _multiline(_steps, 'Как выполнять (шаги)'),
          _multiline(_rules, 'Правила и ограничения'),
          _multiline(_points, 'Подсказки тренера'),
          _multiline(_success, 'Критерии успеха'),
          _multiline(_easier, 'Как упростить'),
          _multiline(_harder, 'Как усложнить'),
        ]),
      ),
    );
  }
}

/// Открыть выбор упражнения из библиотеки (для редактора плана).
Future<Drill?> pickDrill(BuildContext context) =>
    Navigator.of(context).push<Drill>(MaterialPageRoute(builder: (_) => const LibraryScreen(pickMode: true)));


const intensityNames = {'low': 'Низкая', 'medium': 'Средняя', 'high': 'Высокая'};

/// Подробные фильтры каталога: интенсивность, длительность, игроки, возраст, инвентарь.
Future<void> showDrillFiltersSheet(BuildContext context, WidgetRef ref) {
  var f = ref.read(drillFilterProvider);
  var ints = {...f.intensities};
  var maxDur = f.maxDuration;
  var players = f.players;
  var age = f.age;
  Set<String>? eq = f.equipment == null ? null : {...f.equipment!};
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text('Фильтры упражнений', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text('Интенсивность', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            for (final e in intensityNames.entries)
              FilterChip(
                label: Text(e.value),
                selected: ints.contains(e.key),
                onSelected: (v) => set(() => v ? ints.add(e.key) : ints.remove(e.key)),
              ),
          ]),
          const SizedBox(height: 12),
          const Text('Длительность', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            for (final m in [null, 10, 15, 20, 30])
              ChoiceChip(label: Text(m == null ? 'Любая' : 'до $m мин'), selected: maxDur == m, onSelected: (_) => set(() => maxDur = m)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Text('Число игроков', style: TextStyle(fontWeight: FontWeight.w700))),
            Switch(value: players != null, onChanged: (v) => set(() => players = v ? 12 : null)),
          ]),
          if (players != null) ...[
            Text('Подходит для $players игроков'),
            Slider(value: players!.toDouble(), min: 1, max: 30, divisions: 29, label: '$players', onChanged: (v) => set(() => players = v.round())),
          ],
          Row(children: [
            const Expanded(child: Text('Возраст игроков', style: TextStyle(fontWeight: FontWeight.w700))),
            Switch(value: age != null, onChanged: (v) => set(() => age = v ? 12 : null)),
          ]),
          if (age != null) ...[
            Text(age! >= 18 ? 'Взрослые (18+)' : '$age лет'),
            Slider(value: age!.toDouble(), min: 6, max: 18, divisions: 12, label: '$age', onChanged: (v) => set(() => age = v.round())),
          ],
          Row(children: [
            const Expanded(child: Text('Только с моим инвентарём', style: TextStyle(fontWeight: FontWeight.w700))),
            Switch(value: eq != null, onChanged: (v) => set(() => eq = v ? {'balls', 'cones'} : null)),
          ]),
          if (eq != null)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in Equipment.all.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: eq!.contains(e.key),
                  onSelected: (v) => set(() => v ? eq!.add(e.key) : eq!.remove(e.key)),
                ),
            ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  ref.read(drillFilterProvider.notifier).update((s) => s.withExtra());
                  Navigator.pop(c);
                },
                child: const Text('Сбросить'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  ref.read(drillFilterProvider.notifier).update(
                        (s) => s.withExtra(intensities: ints, maxDuration: maxDur, players: players, age: age, equipment: eq),
                      );
                  Navigator.pop(c);
                },
                child: const Text('Показать'),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
}

/// Похожие упражнения: та же категория, близкий возраст и состав.
List<Drill> similarDrills(Drill d, List<Drill> all, {int limit = 4}) {
  int score(Drill x) =>
      (x.category == d.category ? 0 : 100) +
      (x.ageMin - d.ageMin).abs() +
      (x.playersMin - d.playersMin).abs() +
      (x.intensity == d.intensity ? 0 : 3);
  return ([for (final x in all) if (x.id != d.id && (x.category == d.category || x.tags.any(d.tags.contains))) x]
        ..sort((a, b) => score(a).compareTo(score(b))))
      .take(limit)
      .toList();
}
