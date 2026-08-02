import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 偏好存储
class SharedPrefsStorage {
  SharedPrefsStorage(this._prefs, {this.maxHistory = 20});

  final SharedPreferences _prefs;
  final int maxHistory;

  // === 主题 ===
  Future<void> setThemeMode(String mode) =>
      _prefs.setString('pref_theme_mode', mode);
  String getThemeMode() => _prefs.getString('pref_theme_mode') ?? 'system';

  // === 语言 ===
  Future<void> setLocale(String locale) =>
      _prefs.setString('pref_locale', locale);
  String getLocale() => _prefs.getString('pref_locale') ?? 'zh';

  // === 搜索历史 ===
  List<String> getSearchHistory() {
    final raw = _prefs.getString('pref_search_history');
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<String>();
  }

  Future<void> addSearchHistory(String keyword) async {
    if (keyword.trim().isEmpty) return;
    final list = getSearchHistory();
    list.removeWhere((e) => e == keyword);
    list.insert(0, keyword);
    if (list.length > maxHistory) list.removeRange(maxHistory, list.length);
    await _prefs.setString('pref_search_history', jsonEncode(list));
  }

  Future<void> removeSearchHistory(String keyword) async {
    final list = getSearchHistory()..removeWhere((e) => e == keyword);
    await _prefs.setString('pref_search_history', jsonEncode(list));
  }

  Future<void> clearSearchHistory() =>
      _prefs.setString('pref_search_history', jsonEncode(const <String>[]));

  // === 首页频道记忆 ===
  Future<void> setLastDiscoverChannel(String channel) =>
      _prefs.setString('pref_last_discover_channel', channel);
  String getLastDiscoverChannel() =>
      _prefs.getString('pref_last_discover_channel') ?? 'recommend';

  // === 通用键值 ===
  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
  Future<void> remove(String key) => _prefs.remove(key);

  // === 最近选择的位置 ===
  static const _recentLocationsKey = 'pref_recent_locations';
  static const int maxRecentLocations = 8;

  List<String> getRecentLocations() {
    final raw = _prefs.getString(_recentLocationsKey);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<String>();
  }

  Future<void> addRecentLocation(String location) async {
    final t = location.trim();
    if (t.isEmpty) return;
    final list = getRecentLocations()..removeWhere((e) => e == t);
    list.insert(0, t);
    if (list.length > maxRecentLocations) {
      list.removeRange(maxRecentLocations, list.length);
    }
    await _prefs.setString(_recentLocationsKey, jsonEncode(list));
  }

  /// 清空最近位置。
  Future<void> clearRecentLocations() =>
      _prefs.setString(_recentLocationsKey, jsonEncode(const <String>[]));

  // === AI 对话历史 ===
  static const _aiHistoryKey = 'pref_ai_chat_history';
  static const _aiSessionKey = 'pref_ai_session_id';
  static const int maxAiMessages = 100; // 最多保留 100 条，避免占用过大

  String? getAiHistory() => _prefs.getString(_aiHistoryKey);

  Future<void> setAiHistory(String json) =>
      _prefs.setString(_aiHistoryKey, json);

  int? getAiSessionId() {
    final intValue = _prefs.getInt(_aiSessionKey);
    if (intValue != null) return intValue;
    final legacy = _prefs.getString(_aiSessionKey);
    if (legacy == null || legacy.isEmpty) return null;
    final parsed = int.tryParse(legacy);
    if (parsed != null) {
      _prefs.setInt(_aiSessionKey, parsed);
    }
    return parsed;
  }

  /// 保存 AI 会话 ID。
  Future<void> setAiSessionId(int? sessionId) {
    if (sessionId == null) {
      return _prefs.remove(_aiSessionKey);
    }
    return _prefs.setInt(_aiSessionKey, sessionId);
  }

  /// 清空 AI 对话历史。
  Future<void> clearAiHistory() async {
    await _prefs.remove(_aiHistoryKey);
    await _prefs.remove(_aiSessionKey);
  }
}
