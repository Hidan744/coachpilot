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

  /// Поле-родитель для индекса parentId в локальной БД.
  static const parentField = {
    players: 'team_id',
    favorites: 'drill_id',
    sessions: 'team_id',
    attendance: 'session_id',
    notes: 'session_id',
    reports: 'session_id',
    assessments: 'player_id',
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

  const SchemeItem({required this.type, required this.x, required this.y, this.x2, this.y2, this.label});

  bool get isArrow => type.startsWith('arrow_') || type == 'zone';

  factory SchemeItem.fromJson(Json j) => SchemeItem(
        type: j['type'],
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        x2: (j['x2'] as num?)?.toDouble(),
        y2: (j['y2'] as num?)?.toDouble(),
        label: j['label'],
      );

  Json toJson() => {
        'type': type,
        'x': x,
        'y': y,
        if (x2 != null) 'x2': x2,
        if (y2 != null) 'y2': y2,
        if (label != null) 'label': label,
      };

  SchemeItem moved(double dx, double dy) => SchemeItem(
        type: type,
        x: x + dx,
        y: y + dy,
        x2: x2 == null ? null : x2! + dx,
        y2: y2 == null ? null : y2! + dy,
        label: label,
      );
}

class Scheme {
  final String field; // full | half | third | box | grid
  final List<SchemeItem> items;

  const Scheme({this.field = 'half', this.items = const []});

  factory Scheme.fromJson(Json j) => Scheme(
        field: j['field'] ?? 'half',
        items: ((j['items'] as List?) ?? []).map((e) => SchemeItem.fromJson(e as Json)).toList(),
      );

  Json toJson() => {'field': field, 'items': items.map((e) => e.toJson()).toList()};
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
