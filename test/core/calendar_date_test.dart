import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/core/domain/calendar_date.dart';

void main() {
  test('strict parsing rejects normalized overflow and noncanonical dates', () {
    for (final value in [
      null,
      '',
      '2026-02-29',
      '2024-02-30',
      '2026-04-31',
      '2026-13-01',
      '2026-00-10',
      '2026-01-00',
      '0000-01-01',
      '2026-1-01',
      '2026-01-01\n',
      ' 2026-01-01',
      '2026-01-01T00:00:00Z',
    ]) {
      expect(CalendarDate.parse(value), isNull, reason: '$value');
    }
    expect(CalendarDate.parse('2024-02-29'), DateTime.utc(2024, 2, 29));
    expect(CalendarDate.parse('0001-01-01'), DateTime.utc(1, 1, 1));
    expect(CalendarDate.parse('9999-12-31'), DateTime.utc(9999, 12, 31));
  });
  test(
    'range validation uses calendar days including the exact server boundary',
    () {
      final start = DateTime.utc(2026, 1, 1);
      final last = start
          .add(const Duration(days: 3660))
          .toIso8601String()
          .substring(0, 10);
      final beyond = start
          .add(const Duration(days: 3661))
          .toIso8601String()
          .substring(0, 10);
      expect(
        CalendarDate.rangeError('2026-01-01', last, maximumDays: 3660),
        isNull,
      );
      expect(
        CalendarDate.rangeError('2026-01-01', beyond, maximumDays: 3660),
        isNotNull,
      );
      expect(CalendarDate.rangeError('2026-01-02', '2026-01-01'), isNotNull);
      expect(CalendarDate.rangeError('2026-01-01', '2026-01-01'), isNull);
    },
  );
}
