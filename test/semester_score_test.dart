import 'package:flutter_test/flutter_test.dart';
import 'package:bmstu_neo/models/discipline_progress.dart';

const _thresholds = {'point_3': '19', 'point_4': '23', 'point_5': '28', 'point_all': '33'};

ControlEvent _module(String discipline, int i, {String? value, Map<String, dynamic>? points = _thresholds}) =>
    ControlEvent(
      type: 'М',
      title: 'Модуль $i',
      week: i * 6,
      value: value,
      stage: value == null ? null : '13',
      points: points,
      disciplineTitle: discipline,
      controlIndex: i,
    );

DisciplineProgress _disc(String title, List<ControlEvent> controls, {Map<String, dynamic> points = const {}}) =>
    DisciplineProgress(title: title, points: points, controls: controls);

void main() {
  test('A module is on the grade its own thresholds give', () {
    expect(_module('Физика', 1, value: '28').moduleGrade, 5);
    expect(_module('Физика', 1, value: '27').moduleGrade, 4);
    expect(_module('Физика', 1, value: '19').moduleGrade, 3);
    expect(_module('Физика', 1, value: '9').moduleGrade, 2);
    expect(_module('Физика', 1).moduleGrade, isNull);
    expect(_module('Физика', 1, value: '20', points: null).moduleGrade, isNull);
  });

  test('Discipline maximum: LKS figure, else the sum of the modules', () {
    final modules = [_module('Физика', 1, value: '27'), _module('Физика', 2), _module('Физика', 3)];
    expect(_disc('Физика', modules, points: {'point_all': '100'}).maxPoints, 100);
    expect(_disc('Физика', modules).maxPoints, 99);
    expect(_disc('Физика', [_module('Физика', 1, points: null)]).maxPoints, isNull);
    expect(_disc('Физика', modules).gradedMaxPoints, 33);
  });

  test('Semester total adds up every discipline', () {
    final score = SemesterScore.of([
      _disc('Матанализ', [_module('Матанализ', 1, value: '27'), _module('Матанализ', 2)], points: {'point_all': '100'}),
      _disc(
        'Физика',
        [_module('Физика', 1, value: '15'), _module('Физика', 2, value: '30')],
        points: {'point_all': '100'},
      ),
      // No modules (a pass/fail course): not part of the points
      _disc('Физкультура', const []),
    ]);
    expect(score.scored, 72);
    expect(score.gradedMax, 99);
    expect(score.semesterMax, 200);
    expect(score.gradedModules, 3);
    expect(score.totalModules, 4);
    expect(score.percentOfGraded, 73);
    // Матанализ: 27 of 23/28 → «4»; Физика: 45 of 38/46/56 → «3»
    expect(score.disciplinesByGrade, {4: 1, 3: 1});
  });

  test('Before the first grade there is nothing to judge', () {
    final score = SemesterScore.of([
      _disc('Физика', [_module('Физика', 1)]),
    ]);
    expect(score.scored, 0);
    expect(score.percentOfGraded, isNull);
    expect(score.hasModules, isTrue);
    expect(SemesterScore.of(const []).hasModules, isFalse);
  });
}
