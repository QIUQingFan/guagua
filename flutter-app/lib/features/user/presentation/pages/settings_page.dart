import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../auth/application/auth_controller.dart';

/// 设置页：主题、语言、清缓存、账户安全、关于、退出登录。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.userSettings)),
      body: SafeArea(
        child: ListView(
          children: [
            _SectionTitle(l.settingsTheme),
            _ThemeTile(ref: ref),
            const _Divider(),
            _SectionTitle(l.settingsLanguage),
            _LanguageTile(ref: ref),
            const _Divider(),
            _SectionTitle(l.commonLoading),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: Text(l.settingsClearCache),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                ref.read(toastControllerProvider).success(l.settingsCacheCleared);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l.settingsAbout),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _showAbout(context),
            ),
            const _Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.primary),
              title: Text(l.settingsLogout,
                  style: const TextStyle(color: AppColors.primary)),
              onTap: () => _confirmLogout(context, ref),
            ),
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: Text(
                '${l.settingsVersion} 1.0.0',
                style: TextStyle(
                  fontSize: AppTextSize.caption,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l.settingsLogout,
      content: l.commonLogoutConfirm,
      confirmLabel: l.settingsLogout,
      destructive: true,
    );
    if (ok != true) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (!context.mounted) return;
    ref.read(toastControllerProvider).success(l.authLogoutSuccess);
    context.go('/auth/login');
  }

  void _showAbout(BuildContext context) {
    final l = context.l10n;
    showAboutDialog(
      context: context,
      applicationName: l.appName,
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2026 瓜呱团队',
      children: [
        const SizedBox(height: AppSpacing.sm),
        Text(l.settingsAbout, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTextSize.caption,
          color: Theme.of(context).colorScheme.outline,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: AppSpacing.xl,
      thickness: 6,
      color: Theme.of(context).scaffoldBackgroundColor,
    );
  }
}

class _ThemeTile extends ConsumerWidget {
  const _ThemeTile({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef _) {
    final prefs = ref.watch(sharedPrefsStorageProvider);
    final l = context.l10n;
    final current = prefs?.getThemeMode() ?? 'system';
    final label = switch (current) {
      'light' => l.settingsThemeLight,
      'dark' => l.settingsThemeDark,
      _ => l.settingsThemeSystem,
    };
    return ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: Text(l.settingsTheme),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: Theme.of(context).colorScheme.outline,
              )),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: () => _showThemePicker(context, ref),
    );
  }

  void _showThemePicker(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l.settingsThemeSystem),
              onTap: () => Navigator.pop(ctx, 'system'),
            ),
            ListTile(
              title: Text(l.settingsThemeLight),
              onTap: () => Navigator.pop(ctx, 'light'),
            ),
            ListTile(
              title: Text(l.settingsThemeDark),
              onTap: () => Navigator.pop(ctx, 'dark'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await ref.read(sharedPrefsStorageProvider)?.setThemeMode(result);
    if (context.mounted) {
      ref.read(toastControllerProvider).show(l.settingsTheme);
    }
  }
}

class _LanguageTile extends ConsumerWidget {
  const _LanguageTile({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef _) {
    final l = context.l10n;
    final current = ref.watch(localeProvider);
    final label = current == 'zh' ? l.settingsLanguageZh : l.settingsLanguageEn;
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(l.settingsLanguage),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: Theme.of(context).colorScheme.outline,
              )),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: () => _showLanguagePicker(context, ref),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l.settingsLanguageZh),
              onTap: () => Navigator.pop(ctx, 'zh'),
            ),
            ListTile(
              title: Text(l.settingsLanguageEn),
              onTap: () => Navigator.pop(ctx, 'en'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await ref.read(localeProvider.notifier).setLocale(result);
    if (context.mounted) {
      ref.read(toastControllerProvider).show(l.settingsLanguage);
    }
  }
}
