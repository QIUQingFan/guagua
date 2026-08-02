import 'package:flutter_test/flutter_test.dart';
import 'package:guagua/core/utils/formatters.dart';

void main() {
  group('Formatters.count', () {
    test('returns 0 for null', () {
      expect(Formatters.count(null), '0');
    });

    test('returns 0 for negative', () {
      expect(Formatters.count(-5), '0');
    });

    test('returns raw value for <1000', () {
      expect(Formatters.count(0), '0');
      expect(Formatters.count(1), '1');
      expect(Formatters.count(999), '999');
    });

    test('returns 1.0k for 1000', () {
      expect(Formatters.count(1000), '1.0k');
    });

    test('returns 1.5k for 1500', () {
      expect(Formatters.count(1500), '1.5k');
    });

    test('returns 9.9w for 99000 (>=10000 走万分支)', () {
      expect(Formatters.count(99000), '9.9w');
    });

    test('returns 99k for 990 (k 分支无小数场景需 >=100k，即 >=100000 已走 w 分支)', () {
      expect(Formatters.count(1500), '1.5k');
    });

    test('returns 1.0w for 10000', () {
      expect(Formatters.count(10000), '1.0w');
    });

    test('returns 1.5w for 15000', () {
      expect(Formatters.count(15000), '1.5w');
    });

    test('returns 100w for 1000000', () {
      expect(Formatters.count(1000000), '100w');
    });
  });

  group('Formatters.relativeTime', () {
    test('returns empty for null', () {
      expect(Formatters.relativeTime(null), '');
    });

    test('returns 刚刚 for now', () {
      final now = DateTime.now();
      expect(Formatters.relativeTime(now, now: now), '刚刚');
    });

    test('returns x分钟前 for 5 minutes ago', () {
      final now = DateTime(2026, 7, 26, 12, 0);
      final past = now.subtract(const Duration(minutes: 5));
      expect(Formatters.relativeTime(past, now: now), '5分钟前');
    });

    test('returns x小时前 for 3 hours ago', () {
      final now = DateTime(2026, 7, 26, 12, 0);
      final past = now.subtract(const Duration(hours: 3));
      expect(Formatters.relativeTime(past, now: now), '3小时前');
    });

    test('returns x天前 for 3 days ago', () {
      final now = DateTime(2026, 7, 26, 12, 0);
      final past = now.subtract(const Duration(days: 3));
      expect(Formatters.relativeTime(past, now: now), '3天前');
    });

    test('returns MM-dd for older this year', () {
      final now = DateTime(2026, 7, 26, 12, 0);
      final past = DateTime(2026, 7, 1, 0, 0);
      expect(Formatters.relativeTime(past, now: now), '07-01');
    });

    test('returns yyyy-MM-dd for previous year', () {
      final now = DateTime(2026, 7, 26, 12, 0);
      final past = DateTime(2025, 12, 31, 0, 0);
      expect(Formatters.relativeTime(past, now: now), '2025-12-31');
    });

    test('returns 刚刚 for future time', () {
      final now = DateTime(2026, 7, 26, 12, 0);
      final future = now.add(const Duration(minutes: 1));
      expect(Formatters.relativeTime(future, now: now), '刚刚');
    });
  });

  group('Formatters.date', () {
    test('returns empty for null', () {
      expect(Formatters.date(null), '');
    });

    test('returns yyyy-MM-dd', () {
      expect(Formatters.date(DateTime(2026, 7, 26)), '2026-07-26');
    });
  });

  group('Formatters.dateTime', () {
    test('returns empty for null', () {
      expect(Formatters.dateTime(null), '');
    });

    test('returns yyyy-MM-dd HH:mm', () {
      expect(
        Formatters.dateTime(DateTime(2026, 7, 26, 8, 30)),
        '2026-07-26 08:30',
      );
    });
  });

  group('tryParseDateTime', () {
    test('returns null for null input', () {
      expect(tryParseDateTime(null), isNull);
    });

    test('returns null for empty input', () {
      expect(tryParseDateTime(''), isNull);
    });

    test('returns null for invalid input', () {
      expect(tryParseDateTime('not-a-date'), isNull);
    });

    test('parses ISO8601 string', () {
      final dt = tryParseDateTime('2026-07-26T08:30:00.000Z');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
    });
  });
}
