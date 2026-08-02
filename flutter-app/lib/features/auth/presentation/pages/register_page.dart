import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/validators.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../application/auth_controller.dart';
import '../../data/auth_repository.dart' show authApiProvider;

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _userIdCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _captchaCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  String _captchaId = '';
  String _captchaSvg = '';
  bool _captchaLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCaptcha());
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _nicknameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    _captchaCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    if (_captchaLoading) return;
    setState(() => _captchaLoading = true);
    try {
      final dto = await ref.read(authApiProvider).captcha();
      if (!mounted) return;
      setState(() {
        _captchaId = dto.captchaId;
        _captchaSvg = dto.captchaSvg;
        _captchaCtrl.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _captchaSvg = '');
    } finally {
      if (mounted) setState(() => _captchaLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final l = context.l10n;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            userId: _userIdCtrl.text.trim(),
            nickname: _nicknameCtrl.text.trim(),
            password: _passwordCtrl.text,
            captchaId: _captchaId,
            captchaText: _captchaCtrl.text.trim(),
            bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
            location: _locationCtrl.text.trim().isEmpty
                ? null
                : _locationCtrl.text.trim(),
          );
      if (!mounted) return;
      final err = ref.read(authControllerProvider).error;
      if (err != null) {
        ref.read(toastControllerProvider).error(_formatError(err, l));
        unawaited(_loadCaptcha());
      } else {
        ref.read(toastControllerProvider).success(l.authRegisterSuccess);
        context.go('/discover');
      }
    } catch (e) {
      ref.read(toastControllerProvider).error(_formatError(e, l));
      unawaited(_loadCaptcha());
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
                SizedBox(height: MediaQuery.of(context).size.height * 0.08),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new),
                      onPressed: () => context.go('/auth/login'),
                    ),
                  ],
                ),
                Text(
                  l.authWelcome,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _userIdCtrl,
                  decoration: InputDecoration(
                    labelText: l.authUserIdLabel,
                    hintText: l.authUserIdHint,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: Validators.userId,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _nicknameCtrl,
                  decoration: InputDecoration(
                    labelText: l.authNicknameLabel,
                    hintText: l.authNicknameHint,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: Validators.nickname,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: l.authPasswordLabel,
                    hintText: l.authPasswordHint,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: Validators.password,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: l.authConfirmPasswordLabel,
                    hintText: l.authConfirmPasswordHint,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      Validators.confirmPassword(v, _passwordCtrl.text),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _captchaCtrl,
                        decoration: InputDecoration(
                          labelText: l.authCaptchaLabel,
                          hintText: l.authCaptchaHint,
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? l.authCaptchaRequired
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _buildCaptchaImage(l),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _bioCtrl,
                  decoration: InputDecoration(
                    labelText: l.authBioLabel,
                    hintText: l.authBioHint,
                  ),
                  maxLines: 2,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _locationCtrl,
                  decoration: InputDecoration(
                    labelText: l.authLocationLabel,
                    hintText: l.authLocationHint,
                  ),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: AppSpacing.xl),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l.authRegister),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: () => context.go('/auth/login'),
                  child: Text(l.authGoLogin),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 验证码图片
  Widget _buildCaptchaImage(AppLocalizations l) {
    final theme = Theme.of(context);
    return Tooltip(
      message: l.authCaptchaRefresh,
      child: GestureDetector(
        onTap: _captchaLoading ? null : _loadCaptcha,
        child: Container(
          width: 110,
          height: 60,
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          alignment: Alignment.center,
          child: _captchaLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _captchaSvg.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    l.authCaptchaLoadFailed,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SvgPicture.string(
                    _captchaSvg,
                    width: 110,
                    height: 60,
                    fit: BoxFit.contain,
                  ),
                ),
        ),
      ),
    );
  }
}
