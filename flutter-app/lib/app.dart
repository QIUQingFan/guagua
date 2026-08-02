import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/services/local_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'generated/l10n/app_localizations.dart';
import 'shared/providers/core_providers.dart';
import 'shared/widgets/toast_overlay.dart';

class GuaguaApp extends ConsumerStatefulWidget {
  const GuaguaApp({super.key});

  @override
  ConsumerState<GuaguaApp> createState() => _GuaguaAppState();
}

class _GuaguaAppState extends ConsumerState<GuaguaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    final notif = ref.read(localNotificationServiceProvider);
    notif
      ..onTapNotification = _onNotificationTap
      ..init();
  }

  void _onNotificationTap(String payload) {
    final data = LocalNotificationService.decodePayload(payload);
    if (data == null) return;
    final route = data['route'] as String?;
    if (route == null || route.isEmpty) return;
    ref.read(routerProvider).push(route);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final localeCode = ref.watch(localeProvider);

    return MaterialApp.router(
      title: '瓜呱',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      locale: Locale(localeCode),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) {
        return ToastOverlay(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
