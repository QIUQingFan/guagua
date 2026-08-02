/// 本地存储 key 统一管理。
class StorageKeys {
  const StorageKeys._();

  static const accessToken = 'access_token';
  static const refreshToken = 'refresh_token';
  static const userProfile = 'user_profile';

  static const themeMode = 'pref_theme_mode';
  static const locale = 'pref_locale';
  static const searchHistory = 'pref_search_history';
  static const lastDiscoverChannel = 'pref_last_discover_channel';

  // 草稿
  static const publishDraft = 'pref_publish_draft';
}
