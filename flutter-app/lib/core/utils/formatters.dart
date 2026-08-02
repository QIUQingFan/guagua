import 'package:intl/intl.dart';

import '../constants/env.dart';

/// 数值与时间格式化工具。
class Formatters {
  const Formatters._();

  static String count(int? value) {
    if (value == null || value < 0) return '0';
    if (value >= 10000) {
      final w = value / 10000;
      return w >= 100 ? '${w.toStringAsFixed(0)}w' : '${w.toStringAsFixed(1)}w';
    }
    if (value >= 1000) {
      final k = value / 1000;
      return k >= 100 ? '${k.toStringAsFixed(0)}k' : '${k.toStringAsFixed(1)}k';
    }
    return value.toString();
  }

  static String relativeTime(DateTime? time, {DateTime? now}) {
    if (time == null) return '';
    final ref = now ?? DateTime.now();
    final diff = ref.difference(time);
    if (diff.isNegative) return '刚刚';
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    final isThisYear = time.year == ref.year;
    final fmt = isThisYear ? 'MM-dd' : 'yyyy-MM-dd';
    return DateFormat(fmt).format(time);
  }

  static String date(DateTime? time) {
    if (time == null) return '';
    return DateFormat('yyyy-MM-dd').format(time);
  }

  static String dateTime(DateTime? time) {
    if (time == null) return '';
    return DateFormat('yyyy-MM-dd HH:mm').format(time);
  }
}

DateTime? tryParseDateTime(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

num? tryParseNum(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw;
  if (raw is bool) return raw ? 1 : 0;
  var s = raw.toString().trim();
  if (s.startsWith('`')) s = s.substring(1);
  if (s.endsWith('`')) s = s.substring(0, s.length - 1);
  s = s.trim();
  return num.tryParse(s);
}

double parseDouble(Object? raw, {double fallback = 0}) {
  return tryParseNum(raw)?.toDouble() ?? fallback;
}

int parseInt(Object? raw, {int fallback = 0}) {
  return tryParseNum(raw)?.toInt() ?? fallback;
}

String cleanString(Object? raw) {
  if (raw == null) return '';
  var s = raw.toString().trim();
  if (s.startsWith('`')) s = s.substring(1);
  if (s.endsWith('`')) s = s.substring(0, s.length - 1);
  return s.trim();
}

/// 将相对路径图片 URL 补全为完整 URL。
String getFullImageUrl(String url) {
  if (url.isEmpty) return '';
  if (url.startsWith('http://') ||
      url.startsWith('https://') ||
      url.startsWith('data:')) {
    return url;
  }
  final base = Env.apiBaseUrl;
  final host = base.endsWith('/api')
      ? base.substring(0, base.length - 4)
      : base;
  final path = url.startsWith('/') ? url : '/$url';
  return '$host$path';
}
