import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/validators.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../application/auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _userIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final l = context.l10n;
    try {
      await ref.read(authControllerProvider.notifier).login(
            _userIdCtrl.text.trim(),
            _passwordCtrl.text,
          );
      if (!mounted) return;
      final err = ref.read(authControllerProvider).error;
      if (err != null) {
        ref.read(toastControllerProvider).error(_formatError(err, l));
      } else {
        ref.read(toastControllerProvider).success(l.authLoginSuccess);
        context.go('/discover');
      }
    } catch (e) {
      ref.read(toastControllerProvider).error(_formatError(e, l));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _formatError(Object e, AppLocalizations l) {
    if (e is ApiException) {
      return e.message.isEmpty ? l.commonOperationFailed : e.message;
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.16),
                Text(
                  l.authWelcome,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                TextFormField(
                  controller: _userIdCtrl,
                  decoration: InputDecoration(labelText: l.authUserIdLabel, hintText: l.authUserIdHint),
                  textInputAction: TextInputAction.next,
                  validator: Validators.userId,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: l.authPasswordLabel,
                    hintText: l.authPasswordHint,
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  validator: Validators.password,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.xl),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(l.authLogin),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextButton(
                  onPressed: () => context.go('/auth/register'),
                  child: Text(l.authGoRegister),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
