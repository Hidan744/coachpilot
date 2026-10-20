import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models.dart';

final matchStatsProvider = StreamProvider<List<MatchStat>>((ref) => ref.watch(repoProvider).watchMatchStats());

final physicalTestsProvider = StreamProvider<List<PhysicalTest>>((ref) => ref.watch(repoProvider).watchPhysicalTests());

final staffProvider = StreamProvider<List<StaffMember>>((ref) => ref.watch(repoProvider).watchStaff());

final allAssessmentsProvider = StreamProvider<List<PlayerAssessment>>(
  (ref) => ref.watch(repoProvider).watch(Entities.assessments, PlayerAssessment.fromJson),
);

final allReportsProvider = StreamProvider<List<SessionReport>>(
  (ref) => ref.watch(repoProvider).watch(Entities.reports, SessionReport.fromJson),
);

final allDevPlansProvider = StreamProvider<List<DevelopmentPlan>>(
  (ref) => ref.watch(repoProvider).watch(Entities.devPlans, DevelopmentPlan.fromJson),
);
