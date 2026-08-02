import 'package:flutter/widgets.dart';

import '../../generated/l10n/app_localizations.dart';

/// 便捷访问国际化文案。
///
/// 用法：`final l = context.l10n;` → `l.authLogin`
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
