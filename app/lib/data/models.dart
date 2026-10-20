// Доменные модели. Поля и JSON-ключи совпадают со схемами backend (app/schemas.py).

typedef Json = Map<String, dynamic>;

List<String> _strList(dynamic v) => (v as List?)?.map((e) => e.toString()).toList() ?? [];
DateTime? _date(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

abstract class Entity {
  String get id;
  Json toJson();
}

class Entities {
  static const teams = 'teams';
  static const players = 'players';
  static const drills = 'drills';
  static const favorites = 'favorites';
  static const sessions = 'training_sessions';
  static const attendance = 'attendance';
  static const notes = 'session_notes';
  static const reports = 'session_reports';
  static const assessments = 'player_assessments';
  static const matches = 'matches';
  static const slots = 'schedule_slots';
  static const devPlans = 'development_plans';
  static const boards = 'tactic_boards';
  static const parentNotes = 'parent_notes';
  static const matchStats = 'match_stats';
  static const physicalTests = 'physical_tests';
  static const staff = 'staff';

  /// Поле-родитель для индекса parentId в локальной БД.
  static const parentField = {
    players: 'team_id',
    favorites: 'drill_id',
    sessions: 'team_id',
    attendance: 'session_id',
    notes: 'session_id',
    reports: 'session_id',
    assessments: 'player_id',
    matches: 'team_id',
    slots: 'team_id',
    devPlans: 'player_id',
    boards: 'team_id',
    parentNotes: 'player_id',
    matchStats: 'match_id',
    physicalTests: 'player_id',
  };

  /// Сущности, где сервер не перезаписывает правку молча, а возвращает конфликт.
  static const strict = {drills, sessions, reports};
}

// ---------------------------------------------------------------- команда

class AgeGroups {
  static const all = ['U6', 'U7', 'U8', 'U9', 'U10', 'U11', 'U12', 'U13', 'U14', 'U15', 'U16', 'U17', 'U19', 'adult'];
  static String label(String g) => g == 'adult' ? 'Взрослые' : g;

  /// Примерный возраст игроков для фильтрации упражнений.
  static int age(String g) => g == 'adult' ? 18 : int.tryParse(g.substring(1)) ?? 12;
}

class Levels {
  static const all = {'beginner': 'Начальный', 'amateur': 'Любительский', 'advanced': 'Продвинутый', 'pro': 'Профессиональный'};
}

class Team implements Entity {
  @override
  final String id;
  final String name;
  final String ageGroup;
  final String level;
  final int defaultPlayers;
  final String? fieldType;
  final List<String> equipment;
  final String notes;

  Team({
    required this.id,
    required this.name,
    required this.ageGroup,
    required this.level,
    required this.defaultPlayers,
    this.fieldType,
    this.equipment = const [],
    this.notes = '',
  });

  factory Team.fromJson(String id, Json j) => Team(
        id: id,
        name: j['name'] ?? '',
        ageGroup: j['age_group'] ?? 'U12',
        level: j['level'] ?? 'amateur',
        defaultPlayers: j['default_players'] ?? 12,
        fieldType: j['field_type'],
        equipment: _strList(j['equipment']),
        notes: j['notes'] ?? '',
      );

  @override
  Json toJson() => {
        'name': name,
        'age_group': ageGroup,
        'level': level,
        'default_players': defaultPlayers,
        'field_type': fieldType,
        'equipment': equipment,
        'notes': notes,
      };
}

class Positions {
  static const all = {'GK': 'Вратарь', 'DF': 'Защитник', 'MF': 'Полузащитник', 'FW': 'Нападающий'};
}

class Player implements Entity {
  @override
  final String id;
  final String teamId;
  final String firstName;
  final String lastName;
  final int? birthYear;
  final String? position;
  final int? number;
  final String notes;
  final bool active;

  Player({
    required this.id,
    required this.teamId,
    required this.firstName,
    this.lastName = '',
    this.birthYear,
    this.position,
    this.number,
    this.notes = '',
    this.active = true,
  });

  String get fullName => lastName.isEmpty ? firstName : '$firstName $lastName';

  factory Player.fromJson(String id, Json j) => Player(
        id: id,
        teamId: j['team_id'],
        firstName: j['first_name'] ?? '',
        lastName: j['last_name'] ?? '',
        birthYear: j['birth_year'],
        position: j['position'],
        number: j['number'],
        notes: j['notes'] ?? '',
        active: j['active'] ?? true,
      );

  @override
  Json toJson() => {
        'team_id': teamId,
        'first_name': firstName,
        'last_name': lastName,
        'birth_year': birthYear,
        'position': position,
        'number': number,
        'notes': notes,
        'active': active,
      };
}

// ---------------------------------------------------------------- упражнения

class DrillCategories {
  static const all = {
    'warmup': 'Разминка',
    'technique': 'Техника',
    'passing': 'Передачи',
    'dribbling': 'Дриблинг',
    'finishing': 'Удары',
    'possession': 'Владение',
    'tactics': 'Тактика',
    'transition': 'Переходы',
    'defending': 'Оборона',
    'physical': 'Физподготовка',
    'game': 'Игра',
    'cooldown': 'Заминка',
    'goalkeeping': 'Вратари',
  };
}

class Equipment {
  static const all = {
    'balls': 'Мячи',
    'cones': 'Конусы',
    'bibs': 'Манишки',
    'goals': 'Большие ворота',
    'mini_goals': 'Мини-ворота',
    'poles': 'Стойки',
    'ladder': 'Координационная лестница',
    'hurdles': 'Барьеры',
  };
}

class SchemeItem {
  final String type;
  final double x, y;
  final double? x2, y2;
  final String? label;

  /// Шаг анимации для стрелок: стрелки одного шага проигрываются одновременно.
  final int? step;

  /// Линия от руки (pen) или путь движения по точкам (стрелки): точки в координатах поля.
  final List<Offset2>? points;

  /// Цвет линии от руки: #RRGGBB.
  final String? color;

  /// Постоянный id игрока или мяча: на него ссылаются движения и мяч.
  final String? id;

  /// Для движения: кто двигается (id игрока). Без него — старые схемы, двигается ближайший.
  final String? actor;

  /// Для паса: кому (id игрока). Мяч переходит к нему.
  final String? target;

  /// Для мяча: у кого мяч (id игрока). Свободный мяч — без владельца.
  final String? holder;

  const SchemeItem({
    required this.type,
    required this.x,
    required this.y,
    this.x2,
    this.y2,
    this.label,
    this.step,
    this.points,
    this.color,
    this.id,
    this.actor,
    this.target,
    this.holder,
  });

  bool get isArrow => type.startsWith('arrow_') || type == 'zone';
  bool get isMovement => type.startsWith('arrow_');
  bool get isPlayer => const {'player_a', 'player_b', 'neutral', 'goalkeeper'}.contains(type);

  int get stepOrFirst => step ?? 1;

  /// Путь движения: точки, а у старых стрелок — начало и конец.
  List<Offset2> get path => points != null && points!.length >= 2
      ? points!
      : [Offset2(x, y), Offset2(x2 ?? x, y2 ?? y)];

  factory SchemeItem.fromJson(Json j) => SchemeItem(
        type: j['type'],
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        x2: (j['x2'] as num?)?.toDouble(),
        y2: (j['y2'] as num?)?.toDouble(),
        label: j['label'],
        step: (j['step'] as num?)?.toInt(),
        points: (j['points'] as List?)
            ?.map((p) => Offset2(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()))
            .toList(),
        color: j['color'],
        id: j['id'],
        actor: j['actor'],
        target: j['target'],
        holder: j['holder'],
      );

  Json toJson() => {
        'type': type,
        'x': x,
        'y': y,
        if (x2 != null) 'x2': x2,
        if (y2 != null) 'y2': y2,
        if (label != null) 'label': label,
        if (step != null) 'step': step,
        if (points != null) 'points': [for (final p in points!) [_r(p.x), _r(p.y)]],
        if (color != null) 'color': color,
        if (id != null) 'id': id,
        if (actor != null) 'actor': actor,
        if (target != null) 'target': target,
        if (holder != null) 'holder': holder,
      };

  static double _r(double v) => (v * 1000).roundToDouble() / 1000;

  static const _keep = Object();

  /// Копия с изменёнными полями; для nullable-полей передайте null явно, чтобы очистить.
  SchemeItem copyWith({
    double? x,
    double? y,
    Object? x2 = _keep,
    Object? y2 = _keep,
    Object? label = _keep,
    Object? step = _keep,
    Object? points = _keep,
    Object? id = _keep,
    Object? actor = _keep,
    Object? target = _keep,
    Object? holder = _keep,
  }) =>
      SchemeItem(
        type: type,
        x: x ?? this.x,
        y: y ?? this.y,
        x2: identical(x2, _keep) ? this.x2 : x2 as double?,
        y2: identical(y2, _keep) ? this.y2 : y2 as double?,
        label: identical(label, _keep) ? this.label : label as String?,
        step: identical(step, _keep) ? this.step : step as int?,
        points: identical(points, _keep) ? this.points : points as List<Offset2>?,
        color: color,
        id: identical(id, _keep) ? this.id : id as String?,
        actor: identical(actor, _keep) ? this.actor : actor as String?,
        target: identical(target, _keep) ? this.target : target as String?,
        holder: identical(holder, _keep) ? this.holder : holder as String?,
      );

  SchemeItem moved(double dx, double dy) => copyWith(
        x: x + dx,
        y: y + dy,
        x2: x2 == null ? null : x2! + dx,
        y2: y2 == null ? null : y2! + dy,
        points: points?.map((p) => Offset2(p.x + dx, p.y + dy)).toList(),
      );

  SchemeItem withStep(int? s) => copyWith(step: s);

  SchemeItem withLabel(String? l) => copyWith(label: l);
}

/// Точка линии от руки (без зависимости моделей от Flutter).
class Offset2 {
  const Offset2(this.x, this.y);
  final double x, y;
}

class Scheme {
  final String field; // full | full_v | half | third | box | grid
  final List<SchemeItem> items;

  const Scheme({this.field = 'half', this.items = const []});

  factory Scheme.fromJson(Json j) => Scheme(
        field: j['field'] ?? 'half',
        items: ((j['items'] as List?) ?? []).map((e) => SchemeItem.fromJson(e as Json)).toList(),
      );

  Json toJson() => {'field': field, 'items': items.map((e) => e.toJson()).toList()};

  /// Номера шагов анимации по порядку (пусто — двигаться нечему).
  List<int> get steps => (items.where((e) => e.isMovement).map((e) => e.stepOrFirst).toSet().toList()..sort());
}

class Drill implements Entity {
  @override
  final String id;
  final String source; // system | user | ai
  final String title;
  final String category;
  final String goal;
  final int ageMin, ageMax, playersMin, playersMax, durationMin;
  final String fieldSize;
  final String intensity;
  final List<String> equipment;
  final String setup;
  final List<String> steps, rules, coachingPoints, successCriteria;
  final List<String> easier, harder;
  final Scheme? scheme;
  final List<String> tags;

  Drill({
    required this.id,
    this.source = 'user',
    required this.title,
    required this.category,
    this.goal = '',
    this.ageMin = 6,
    this.ageMax = 99,
    this.playersMin = 1,
    this.playersMax = 30,
    this.durationMin = 10,
    this.fieldSize = '',
    this.intensity = 'medium',
    this.equipment = const [],
    this.setup = '',
    this.steps = const [],
    this.rules = const [],
    this.coachingPoints = const [],
    this.successCriteria = const [],
    this.easier = const [],
    this.harder = const [],
    this.scheme,
    this.tags = const [],
  });

  bool get isSystem => source == 'system';

  factory Drill.fromJson(String id, Json j) {
    final variants = (j['variants'] as Json?) ?? {};
    return Drill(
      id: id,
      source: j['source'] ?? 'user',
      title: j['title'] ?? '',
      category: j['category'] ?? 'technique',
      goal: j['goal'] ?? '',
      ageMin: j['age_min'] ?? 6,
      ageMax: j['age_max'] ?? 99,
      playersMin: j['players_min'] ?? 1,
      playersMax: j['players_max'] ?? 30,
      durationMin: j['duration_min'] ?? 10,
      fieldSize: j['field_size'] ?? '',
      intensity: j['intensity'] ?? 'medium',
      equipment: _strList(j['equipment']),
      setup: j['setup'] ?? '',
      steps: _strList(j['steps']),
      rules: _strList(j['rules']),
      coachingPoints: _strList(j['coaching_points']),
      successCriteria: _strList(j['success_criteria']),
      easier: _strList(variants['easier']),
      harder: _strList(variants['harder']),
      scheme: j['scheme'] == null ? null : Scheme.fromJson(j['scheme'] as Json),
      tags: _strList(j['tags']),
    );
  }

  @override
  Json toJson() => {
        'source': source,
        'title': title,
        'category': category,
        'goal': goal,
        'age_min': ageMin,
        'age_max': ageMax,
        'players_min': playersMin,
        'players_max': playersMax,
        'duration_min': durationMin,
        'field_size': fieldSize,
        'intensity': intensity,
        'equipment': equipment,
        'setup': setup,
        'steps': steps,
        'rules': rules,
        'coaching_points': coachingPoints,
        'success_criteria': successCriteria,
        'variants': {'easier': easier, 'harder': harder},
        'scheme': scheme?.toJson(),
        'tags': tags,
      };
}

// ---------------------------------------------------------------- занятия

class Phases {
  static const all = {'warmup': 'Разминка', 'main': 'Основная часть', 'game': 'Игровая часть', 'cooldown': 'Заминка'};
}

class TrainingBlock {
  final String id;
  final String phase;
  final String title;
  final int durationMin;
  final String? drillId;
  final Json? drill; // снимок упражнения
  final String notes;

  const TrainingBlock({
    required this.id,
    required this.phase,
    required this.title,
    required this.durationMin,
    this.drillId,
    this.drill,
    this.notes = '',
  });

  Drill? get drillSnapshot => drill == null ? null : Drill.fromJson(drillId ?? id, drill!);

  factory TrainingBlock.fromJson(Json j) => TrainingBlock(
        id: j['id'],
        phase: j['phase'],
        title: j['title'],
        durationMin: j['duration_min'],
        drillId: j['drill_id'],
        drill: j['drill'] as Json?,
        notes: j['notes'] ?? '',
      );

  Json toJson() => {
        'id': id,
        'phase': phase,
        'title': title,
        'duration_min': durationMin,
        'drill_id': drillId,
        'drill': drill,
        'notes': notes,
      };

  TrainingBlock copyWith({String? phase, String? title, int? durationMin, String? notes}) => TrainingBlock(
        id: id,
        phase: phase ?? this.phase,
        title: title ?? this.title,
        durationMin: durationMin ?? this.durationMin,
        drillId: drillId,
        drill: drill,
        notes: notes ?? this.notes,
      );
}

class SessionStatus {
  static const labels = {
    'draft': 'Черновик',
    'planned': 'Запланирована',
    'in_progress': 'Идёт',
    'done': 'Проведена',
    'cancelled': 'Отменена',
  };
}

class TrainingSession implements Entity {
  @override
  final String id;
  final String? teamId;
  final String title;
  final DateTime? scheduledAt;
  final String goal;
  final int durationMin;
  final int? playersExpected;
  final String? fieldType;
  final List<String> equipment;
  final String status;
  final bool aiGenerated;
  final List<String> aiAssumptions;
  final List<TrainingBlock> blocks;
  final DateTime? startedAt, finishedAt;

  /// Фактическое время по блокам: {block_id: секунды}, плюс skipped: [...]
  final Json actual;
  final String? conflictOf;

  TrainingSession({
    required this.id,
    this.teamId,
    required this.title,
    this.scheduledAt,
    this.goal = '',
    required this.durationMin,
    this.playersExpected,
    this.fieldType,
    this.equipment = const [],
    this.status = 'draft',
    this.aiGenerated = false,
    this.aiAssumptions = const [],
    this.blocks = const [],
    this.startedAt,
    this.finishedAt,
    this.actual = const {},
    this.conflictOf,
  });

  int get plannedMinutes => blocks.fold(0, (a, b) => a + b.durationMin);

  factory TrainingSession.fromJson(String id, Json j) => TrainingSession(
        id: id,
        teamId: j['team_id'],
        title: j['title'] ?? '',
        scheduledAt: _date(j['scheduled_at']),
        goal: j['goal'] ?? '',
        durationMin: j['duration_min'] ?? 60,
        playersExpected: j['players_expected'],
        fieldType: j['field_type'],
        equipment: _strList(j['equipment']),
        status: j['status'] ?? 'draft',
        aiGenerated: j['ai_generated'] ?? false,
        aiAssumptions: _strList(j['ai_assumptions']),
        blocks: ((j['blocks'] as List?) ?? []).map((e) => TrainingBlock.fromJson(e as Json)).toList(),
        startedAt: _date(j['started_at']),
        finishedAt: _date(j['finished_at']),
        actual: (j['actual'] as Json?) ?? {},
        conflictOf: j['conflict_of'],
      );

  @override
  Json toJson() => {
        'team_id': teamId,
        'title': title,
        'scheduled_at': _iso(scheduledAt),
        'goal': goal,
        'duration_min': durationMin,
        'players_expected': playersExpected,
        'field_type': fieldType,
        'equipment': equipment,
        'status': status,
        'ai_generated': aiGenerated,
        'ai_assumptions': aiAssumptions,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'started_at': _iso(startedAt),
        'finished_at': _iso(finishedAt),
        'actual': actual,
        'conflict_of': conflictOf,
      };

  TrainingSession copyWith({
    String? teamId,
    String? title,
    DateTime? scheduledAt,
    String? goal,
    int? durationMin,
    int? playersExpected,
    String? status,
    List<TrainingBlock>? blocks,
    DateTime? startedAt,
    DateTime? finishedAt,
    Json? actual,
  }) =>
      TrainingSession(
        id: id,
        teamId: teamId ?? this.teamId,
        title: title ?? this.title,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        goal: goal ?? this.goal,
        durationMin: durationMin ?? this.durationMin,
        playersExpected: playersExpected ?? this.playersExpected,
        fieldType: fieldType,
        equipment: equipment,
        status: status ?? this.status,
        aiGenerated: aiGenerated,
        aiAssumptions: aiAssumptions,
        blocks: blocks ?? this.blocks,
        startedAt: startedAt ?? this.startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        actual: actual ?? this.actual,
        conflictOf: conflictOf,
      );
}

class AttendanceStatus {
  static const labels = {
    'present': 'Был',
    'late': 'Опоздал',
    'absent': 'Не был',
    'injured': 'Травма',
    'excused': 'Уважит.',
  };
}

class Attendance implements Entity {
  @override
  final String id;
  final String sessionId, playerId, status;

  Attendance({required this.id, required this.sessionId, required this.playerId, required this.status});

  factory Attendance.fromJson(String id, Json j) =>
      Attendance(id: id, sessionId: j['session_id'], playerId: j['player_id'], status: j['status']);

  @override
  Json toJson() => {'session_id': sessionId, 'player_id': playerId, 'status': status};
}

class SessionNote implements Entity {
  @override
  final String id;
  final String sessionId;
  final String? blockId;
  final String text;
  final DateTime notedAt;

  SessionNote({required this.id, required this.sessionId, this.blockId, required this.text, required this.notedAt});

  factory SessionNote.fromJson(String id, Json j) => SessionNote(
        id: id,
        sessionId: j['session_id'],
        blockId: j['block_id'],
        text: j['text'] ?? '',
        notedAt: _date(j['noted_at']) ?? DateTime.now(),
      );

  @override
  Json toJson() => {'session_id': sessionId, 'block_id': blockId, 'text': text, 'noted_at': _iso(notedAt)};
}

class SessionReport implements Entity {
  @override
  final String id;
  final String sessionId;
  final String rawInput;
  final int? rating;
  final String wentWell, toImprove, observations;
  final List<String> aiSuggestions;
  final bool coachConfirmed;
  final DateTime? confirmedAt;

  /// Нагрузка занятия по ощущениям (RPE 1–10): нагрузка = RPE × минуты.
  final int? rpe;

  SessionReport({
    required this.id,
    required this.sessionId,
    this.rawInput = '',
    this.rating,
    this.wentWell = '',
    this.toImprove = '',
    this.observations = '',
    this.aiSuggestions = const [],
    this.coachConfirmed = false,
    this.confirmedAt,
    this.rpe,
  });

  factory SessionReport.fromJson(String id, Json j) => SessionReport(
        id: id,
        sessionId: j['session_id'],
        rawInput: j['raw_input'] ?? '',
        rating: j['rating'],
        wentWell: j['went_well'] ?? '',
        toImprove: j['to_improve'] ?? '',
        observations: j['observations'] ?? '',
        aiSuggestions: _strList(j['ai_suggestions']),
        coachConfirmed: j['coach_confirmed'] ?? false,
        confirmedAt: _date(j['confirmed_at']),
        rpe: j['rpe'],
      );

  @override
  Json toJson() => {
        'session_id': sessionId,
        'raw_input': rawInput,
        'rating': rating,
        'went_well': wentWell,
        'to_improve': toImprove,
        'observations': observations,
        'ai_suggestions': aiSuggestions,
        'coach_confirmed': coachConfirmed,
        'confirmed_at': _iso(confirmedAt),
        'rpe': rpe,
      };
}

class Skills {
  static const all = {
    'technique': 'Техника',
    'passing': 'Передачи',
    'dribbling': 'Дриблинг',
    'finishing': 'Завершение',
    'positioning': 'Позиционирование',
    'decision': 'Принятие решений',
    'physical': 'Физика',
    'attitude': 'Отношение',
  };
}

class PlayerAssessment implements Entity {
  @override
  final String id;
  final String playerId;
  final String? sessionId;
  final String skill;
  final int score;
  final String comment;
  final DateTime assessedAt;

  PlayerAssessment({
    required this.id,
    required this.playerId,
    this.sessionId,
    required this.skill,
    required this.score,
    this.comment = '',
    required this.assessedAt,
  });

  factory PlayerAssessment.fromJson(String id, Json j) => PlayerAssessment(
        id: id,
        playerId: j['player_id'],
        sessionId: j['session_id'],
        skill: j['skill'],
        score: j['score'],
        comment: j['comment'] ?? '',
        assessedAt: _date(j['assessed_at']) ?? DateTime.now(),
      );

  @override
  Json toJson() => {
        'player_id': playerId,
        'session_id': sessionId,
        'skill': skill,
        'score': score,
        'comment': comment,
        'assessed_at': _iso(assessedAt),
      };
}

// ---------------------------------------------------------------- календарь

String? _day(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime? _parseDay(dynamic v) => v == null ? null : DateTime.tryParse(v as String);

class MatchStatus {
  static const labels = {'scheduled': 'Запланирован', 'played': 'Сыгран', 'cancelled': 'Отменён'};
}

class Match implements Entity {
  @override
  final String id;
  final String teamId;
  final String opponent;
  final DateTime startsAt;
  final int durationMin;
  final bool home;
  final String venue, competition, status, notes;
  final int? scoreFor, scoreAgainst;

  Match({
    required this.id,
    required this.teamId,
    required this.opponent,
    required this.startsAt,
    this.durationMin = 90,
    this.home = true,
    this.venue = '',
    this.competition = '',
    this.status = 'scheduled',
    this.scoreFor,
    this.scoreAgainst,
    this.notes = '',
  });

  bool get hasScore => scoreFor != null && scoreAgainst != null;
  String get score => hasScore ? '$scoreFor:$scoreAgainst' : '';

  factory Match.fromJson(String id, Json j) => Match(
        id: id,
        teamId: j['team_id'],
        opponent: j['opponent'] ?? '',
        startsAt: _date(j['starts_at']) ?? DateTime.now(),
        durationMin: j['duration_min'] ?? 90,
        home: j['home'] ?? true,
        venue: j['venue'] ?? '',
        competition: j['competition'] ?? '',
        status: j['status'] ?? 'scheduled',
        scoreFor: j['score_for'],
        scoreAgainst: j['score_against'],
        notes: j['notes'] ?? '',
      );

  @override
  Json toJson() => {
        'team_id': teamId,
        'opponent': opponent,
        'starts_at': _iso(startsAt),
        'duration_min': durationMin,
        'home': home,
        'venue': venue,
        'competition': competition,
        'status': status,
        'score_for': scoreFor,
        'score_against': scoreAgainst,
        'notes': notes,
      };
}

class Weekdays {
  static const short = ['', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
}

/// Регулярная тренировка: дни недели и время, действует в пределах дат сезона.
class ScheduleSlot implements Entity {
  @override
  final String id;
  final String teamId;
  final String title;
  final List<int> weekdays;
  final String startTime; // HH:MM
  final int durationMin;
  final String location;
  final DateTime? validFrom, validTo;
  final String notes;

  ScheduleSlot({
    required this.id,
    required this.teamId,
    required this.title,
    required this.weekdays,
    required this.startTime,
    this.durationMin = 90,
    this.location = '',
    this.validFrom,
    this.validTo,
    this.notes = '',
  });

  int get startMinutes {
    final p = startTime.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  String get endTime {
    final m = startMinutes + durationMin;
    return '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  String get daysLabel => weekdays.map((d) => Weekdays.short[d]).join(', ');

  /// Идёт ли тренировка в этот день (дата без времени).
  bool occursOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (!weekdays.contains(d.weekday)) return false;
    if (validFrom != null && d.isBefore(DateTime(validFrom!.year, validFrom!.month, validFrom!.day))) return false;
    if (validTo != null && d.isAfter(DateTime(validTo!.year, validTo!.month, validTo!.day))) return false;
    return true;
  }

  factory ScheduleSlot.fromJson(String id, Json j) => ScheduleSlot(
        id: id,
        teamId: j['team_id'],
        title: j['title'] ?? '',
        weekdays: ((j['weekdays'] as List?) ?? []).map((e) => (e as num).toInt()).toList(),
        startTime: j['start_time'] ?? '10:00',
        durationMin: j['duration_min'] ?? 90,
        location: j['location'] ?? '',
        validFrom: _parseDay(j['valid_from']),
        validTo: _parseDay(j['valid_to']),
        notes: j['notes'] ?? '',
      );

  @override
  Json toJson() => {
        'team_id': teamId,
        'title': title,
        'weekdays': (weekdays.toSet().toList()..sort()),
        'start_time': startTime,
        'duration_min': durationMin,
        'location': location,
        'valid_from': _day(validFrom),
        'valid_to': _day(validTo),
        'notes': notes,
      };
}

// ---------------------------------------------------------------- развитие игрока

class PlanPeriods {
  static const all = {'week': 'Неделя', 'cycle4': '4 недели', 'cycle6': '6 недель', 'month': 'Месяц', 'season': 'Сезон'};
}

/// Показатель программы развития: сейчас → цель, как измеряем.
class PlanTarget {
  final String name;
  final double? current, target;
  final String unit, measure, comment;
  final String priority; // high | medium | low

  const PlanTarget({
    required this.name,
    this.current,
    this.target,
    this.unit = '',
    this.measure = '',
    this.comment = '',
    this.priority = 'medium',
  });

  static const priorities = {'high': 'Высокий', 'medium': 'Средний', 'low': 'Поддерживающий'};

  /// Разрыв до цели (по модулю): для «меньше — лучше» цель ниже текущего.
  double? get gap => current == null || target == null ? null : (target! - current!).abs();

  /// Доля пути к цели 0..1 (от нуля шкалы); для «меньше — лучше» — отношение цели к текущему.
  double get progress {
    if (current == null || target == null || target == 0) return 0;
    final lowerBetter = target! < current!;
    final v = lowerBetter ? target! / current! : current! / target!;
    return v.clamp(0.0, 1.0);
  }

  factory PlanTarget.fromJson(Json j) => PlanTarget(
        name: j['name'] ?? '',
        current: (j['current'] as num?)?.toDouble(),
        target: (j['target'] as num?)?.toDouble(),
        unit: j['unit'] ?? '',
        measure: j['measure'] ?? '',
        comment: j['comment'] ?? '',
        priority: j['priority'] ?? 'medium',
      );

  Json toJson() => {
        'name': name,
        'current': current,
        'target': target,
        'unit': unit,
        'measure': measure,
        'comment': comment,
        'priority': priority,
      };
}

class PlanItem {
  final String text;
  final String kind; // goal | task
  final bool done;

  const PlanItem({required this.text, this.kind = 'task', this.done = false});

  factory PlanItem.fromJson(Json j) => PlanItem(text: j['text'] ?? '', kind: j['kind'] ?? 'task', done: j['done'] ?? false);

  Json toJson() => {'text': text, 'kind': kind, 'done': done};

  PlanItem copyWith({String? text, String? kind, bool? done}) =>
      PlanItem(text: text ?? this.text, kind: kind ?? this.kind, done: done ?? this.done);
}

/// Индивидуальный план развития игрока на неделю, месяц или сезон.
class DevelopmentPlan implements Entity {
  @override
  final String id;
  final String playerId;
  final String period;
  final String title;
  final DateTime? startsOn, endsOn;
  final List<String> focus;
  final List<PlanItem> items;
  final String comment;

  /// Видно игроку и родителям по ссылке.
  final bool shared;

  /// Ключевая цель программы и показатели «сейчас → цель».
  final String keyGoal;
  final List<PlanTarget> targets;

  DevelopmentPlan({
    required this.id,
    required this.playerId,
    required this.period,
    required this.title,
    this.startsOn,
    this.endsOn,
    this.focus = const [],
    this.items = const [],
    this.comment = '',
    this.shared = true,
    this.keyGoal = '',
    this.targets = const [],
  });

  int get doneCount => items.where((i) => i.done).length;

  factory DevelopmentPlan.fromJson(String id, Json j) => DevelopmentPlan(
        id: id,
        playerId: j['player_id'],
        period: j['period'] ?? 'week',
        title: j['title'] ?? '',
        startsOn: _parseDay(j['starts_on']),
        endsOn: _parseDay(j['ends_on']),
        focus: _strList(j['focus']),
        items: ((j['items'] as List?) ?? []).map((e) => PlanItem.fromJson(e as Json)).toList(),
        comment: j['comment'] ?? '',
        shared: j['shared'] ?? true,
        keyGoal: j['key_goal'] ?? '',
        targets: ((j['targets'] as List?) ?? []).map((e) => PlanTarget.fromJson(e as Json)).toList(),
      );

  @override
  Json toJson() => {
        'player_id': playerId,
        'period': period,
        'title': title,
        'starts_on': _day(startsOn),
        'ends_on': _day(endsOn),
        'focus': focus,
        'items': items.map((i) => i.toJson()).toList(),
        'comment': comment,
        'shared': shared,
        'key_goal': keyGoal,
        'targets': targets.map((t) => t.toJson()).toList(),
      };

  DevelopmentPlan copyWith({List<PlanItem>? items}) => DevelopmentPlan(
        id: id,
        playerId: playerId,
        period: period,
        title: title,
        startsOn: startsOn,
        endsOn: endsOn,
        focus: focus,
        items: items ?? this.items,
        comment: comment,
        shared: shared,
        keyGoal: keyGoal,
        targets: targets,
      );
}

// ---------------------------------------------------------------- тактика

class TacticBoard implements Entity {
  @override
  final String id;
  final String? teamId, matchId;
  final String title;
  final String formation;
  final Scheme scheme;
  final String notes;
  final DateTime? updatedAt;

  TacticBoard({
    required this.id,
    this.teamId,
    this.matchId,
    required this.title,
    this.formation = '',
    this.scheme = const Scheme(field: 'full_v'),
    this.notes = '',
    this.updatedAt,
  });

  factory TacticBoard.fromJson(String id, Json j) => TacticBoard(
        id: id,
        teamId: j['team_id'],
        matchId: j['match_id'],
        title: j['title'] ?? '',
        formation: j['formation'] ?? '',
        scheme: Scheme.fromJson((j['scheme'] as Json?) ?? const {'field': 'full_v'}),
        notes: j['notes'] ?? '',
      );

  @override
  Json toJson() => {
        'team_id': teamId,
        'match_id': matchId,
        'title': title,
        'formation': formation,
        'scheme': scheme.toJson(),
        'notes': notes,
      };
}

// ---------------------------------------------------------------- родителям

class ParentNoteCategories {
  static const all = {
    'general': 'Общее',
    'psychology': 'Психология',
    'nutrition': 'Питание',
    'extra_training': 'Доп. тренировки',
    'health': 'Здоровье',
    'behavior': 'Дисциплина',
  };
}

/// Сообщение тренера родителям об игроке.
class ParentNote implements Entity {
  @override
  final String id;
  final String playerId;
  final String category;
  final String text;
  final DateTime writtenAt;
  final bool shared;

  ParentNote({
    required this.id,
    required this.playerId,
    required this.category,
    required this.text,
    required this.writtenAt,
    this.shared = true,
  });

  factory ParentNote.fromJson(String id, Json j) => ParentNote(
        id: id,
        playerId: j['player_id'],
        category: j['category'] ?? 'general',
        text: j['text'] ?? '',
        writtenAt: _date(j['written_at']) ?? DateTime.now(),
        shared: j['shared'] ?? true,
      );

  @override
  Json toJson() => {
        'player_id': playerId,
        'category': category,
        'text': text,
        'written_at': _iso(writtenAt),
        'shared': shared,
      };
}

// ---------------------------------------------------------------- статистика и ОФП

/// Статистика игрока в матче. id = uuid5(match_id, player_id): одна запись на игрока и матч.
class MatchStat implements Entity {
  @override
  final String id;
  final String matchId, playerId;
  final bool started;
  final int minutes;
  final double? rating;

  /// Счётчики: goals, assists, shots, … (см. StatKeys).
  final Map<String, double> stats;

  MatchStat({
    required this.id,
    required this.matchId,
    required this.playerId,
    this.started = false,
    this.minutes = 0,
    this.rating,
    this.stats = const {},
  });

  double operator [](String key) => stats[key] ?? 0;

  factory MatchStat.fromJson(String id, Json j) => MatchStat(
        id: id,
        matchId: j['match_id'],
        playerId: j['player_id'],
        started: j['started'] ?? false,
        minutes: (j['minutes'] as num?)?.toInt() ?? 0,
        rating: (j['rating'] as num?)?.toDouble(),
        stats: {for (final e in ((j['stats'] as Json?) ?? {}).entries) e.key: (e.value as num).toDouble()},
      );

  @override
  Json toJson() => {
        'match_id': matchId,
        'player_id': playerId,
        'started': started,
        'minutes': minutes,
        'rating': rating,
        'stats': {for (final e in stats.entries) if (e.value != 0) e.key: e.value},
      };

  MatchStat copyWith({bool? started, int? minutes, Object? rating = _keepRating, Map<String, double>? stats}) => MatchStat(
        id: id,
        matchId: matchId,
        playerId: playerId,
        started: started ?? this.started,
        minutes: minutes ?? this.minutes,
        rating: identical(rating, _keepRating) ? this.rating : rating as double?,
        stats: stats ?? this.stats,
      );

  static const _keepRating = Object();
}

/// Тестирование ОФП: результаты тестов на дату (см. PhysicalMetrics).
class PhysicalTest implements Entity {
  @override
  final String id;
  final String playerId;
  final DateTime testedOn;
  final Map<String, double> results;
  final String notes;

  PhysicalTest({required this.id, required this.playerId, required this.testedOn, this.results = const {}, this.notes = ''});

  factory PhysicalTest.fromJson(String id, Json j) => PhysicalTest(
        id: id,
        playerId: j['player_id'],
        testedOn: _parseDay(j['tested_on']) ?? DateTime.now(),
        results: {for (final e in ((j['results'] as Json?) ?? {}).entries) e.key: (e.value as num).toDouble()},
        notes: j['notes'] ?? '',
      );

  @override
  Json toJson() => {'player_id': playerId, 'tested_on': _day(testedOn), 'results': results, 'notes': notes};
}

class StaffRoles {
  static const all = {
    'head': 'Главный тренер',
    'assistant': 'Тренер-ассистент',
    'goalkeeper': 'Тренер вратарей',
    'fitness': 'Тренер по ОФП',
    'doctor': 'Врач / физиотерапевт',
    'analyst': 'Аналитик',
    'other': 'Другое',
  };
}

/// Член тренерского штаба.
class StaffMember implements Entity {
  @override
  final String id;
  final String name, role, phone, email, notes;
  final List<String> teamIds;

  StaffMember({
    required this.id,
    required this.name,
    required this.role,
    this.phone = '',
    this.email = '',
    this.teamIds = const [],
    this.notes = '',
  });

  factory StaffMember.fromJson(String id, Json j) => StaffMember(
        id: id,
        name: j['name'] ?? '',
        role: j['role'] ?? 'other',
        phone: j['phone'] ?? '',
        email: j['email'] ?? '',
        teamIds: _strList(j['team_ids']),
        notes: j['notes'] ?? '',
      );

  @override
  Json toJson() => {'name': name, 'role': role, 'phone': phone, 'email': email, 'team_ids': teamIds, 'notes': notes};
}
