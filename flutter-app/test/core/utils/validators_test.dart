import 'package:flutter_test/flutter_test.dart';
import 'package:guagua/core/utils/validators.dart';

void main() {
  group('Validators.userId', () {
    test('returns error for null', () {
      expect(Validators.userId(null), '请输入瓜呱号');
    });

    test('returns error for empty', () {
      expect(Validators.userId(''), '请输入瓜呱号');
    });

    test('returns error for whitespace only', () {
      expect(Validators.userId('   '), '请输入瓜呱号');
    });

    test('returns error for too short (2 chars)', () {
      expect(Validators.userId('ab'), '瓜呱号为 3-20 位字母、数字或下划线');
    });

    test('returns error for too long (21 chars)', () {
      expect(Validators.userId('a' * 21), '瓜呱号为 3-20 位字母、数字或下划线');
    });

    test('returns error for invalid chars (含中文)', () {
      expect(Validators.userId('瓜呱123'), '瓜呱号为 3-20 位字母、数字或下划线');
    });

    test('returns error for invalid chars (含特殊符号)', () {
      expect(Validators.userId('ab@cd'), '瓜呱号为 3-20 位字母、数字或下划线');
    });

    test('returns null for valid (字母+数字+下划线)', () {
      expect(Validators.userId('user_001'), isNull);
    });

    test('returns null for valid (纯字母)', () {
      expect(Validators.userId('abc'), isNull);
    });

    test('returns null for valid (字母数字混合)', () {
      expect(Validators.userId('guagua123'), isNull);
    });

    test('returns null for boundary (3 chars)', () {
      expect(Validators.userId('abc'), isNull);
    });

    test('returns null for boundary (20 chars)', () {
      expect(Validators.userId('a' * 20), isNull);
    });
  });

  group('Validators.password', () {
    test('returns error for null', () {
      expect(Validators.password(null), '请输入密码');
    });

    test('returns error for empty', () {
      expect(Validators.password(''), '请输入密码');
    });

    test('returns error for too short (5 chars)', () {
      expect(Validators.password('12345'), '密码长度需为 6-20 位');
    });

    test('returns error for too long (21 chars)', () {
      expect(Validators.password('a' * 21), '密码长度需为 6-20 位');
    });

    test('returns null for valid (6 chars)', () {
      expect(Validators.password('123456'), isNull);
    });

    test('returns null for valid (20 chars)', () {
      expect(Validators.password('a' * 20), isNull);
    });

    test('returns null for valid (含中文/特殊符号)', () {
      expect(Validators.password('瓜呱@123'), isNull);
    });
  });

  group('Validators.nickname', () {
    test('returns error for null', () {
      expect(Validators.nickname(null), '请输入昵称');
    });

    test('returns error for empty', () {
      expect(Validators.nickname(''), '请输入昵称');
    });

    test('returns error for whitespace only', () {
      expect(Validators.nickname('   '), '请输入昵称');
    });

    test('returns error for too long (21 chars)', () {
      expect(Validators.nickname('a' * 21), '昵称最长 20 位');
    });

    test('returns null for valid', () {
      expect(Validators.nickname('瓜呱'), isNull);
    });

    test('returns null for boundary (20 chars)', () {
      expect(Validators.nickname('a' * 20), isNull);
    });

    test('trims whitespace before validation', () {
      expect(Validators.nickname('  瓜呱  '), isNull);
    });
  });

  group('Validators.confirmPassword', () {
    test('returns error for null', () {
      expect(Validators.confirmPassword(null, '123456'), '请再次输入密码');
    });

    test('returns error for empty', () {
      expect(Validators.confirmPassword('', '123456'), '请再次输入密码');
    });

    test('returns error for mismatch', () {
      expect(Validators.confirmPassword('123456', '654321'), '两次输入的密码不一致');
    });

    test('returns null for match', () {
      expect(Validators.confirmPassword('123456', '123456'), isNull);
    });
  });

  group('Validators.required', () {
    test('returns error for null', () {
      expect(Validators.required(null), '该项不能为空');
    });

    test('returns error for empty', () {
      expect(Validators.required(''), '该项不能为空');
    });

    test('returns error for whitespace', () {
      expect(Validators.required('   '), '该项不能为空');
    });

    test('uses custom label', () {
      expect(Validators.required('', label: '昵称'), '昵称不能为空');
    });

    test('returns null for non-empty', () {
      expect(Validators.required('content'), isNull);
    });
  });
}
