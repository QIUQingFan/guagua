import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../post/data/publish_repository.dart';
import '../../../post/data/upload_api.dart';
import '../../application/user_profile_controller.dart';
import '../../data/user_repository.dart';

/// 编辑资料页：修改头像、昵称、简介、属地及个性标签（与 web 端一致）。
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _majorCtrl = TextEditingController();
  final _newInterestCtrl = TextEditingController();
  String _avatar = '';
  bool _submitting = false;
  bool _initialized = false;

  String? _gender;
  String? _zodiacSign;
  String? _mbti;
  String? _education;
  final List<String> _interests = [];

  static const _genderOptions = ['', '男', '女'];
  static const _zodiacOptions = [
    '',
    '白羊座',
    '金牛座',
    '双子座',
    '巨蟹座',
    '狮子座',
    '处女座',
    '天秤座',
    '天蝎座',
    '射手座',
    '摩羯座',
    '水瓶座',
    '双鱼座',
  ];
  static const _educationOptions = ['', '高中及以下', '大专', '本科', '硕士', '博士'];
  static const _mbtiOptions = [
    '',
    'INTJ',
    'INTP',
    'ENTJ',
    'ENTP',
    'INFJ',
    'INFP',
    'ENFJ',
    'ENFP',
    'ISTJ',
    'ISFJ',
    'ESTJ',
    'ESFJ',
    'ISTP',
    'ISFP',
    'ESTP',
    'ESFP',
  ];

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    _majorCtrl.dispose();
    _newInterestCtrl.dispose();
    super.dispose();
  }

  void _ensureInit() {
    if (_initialized) return;
    final user = ref.read(currentUserProvider);
    if (user != null) {
      _nicknameCtrl.text = user.nickname;
      _bioCtrl.text = user.bio;
      _locationCtrl.text = user.location;
      _majorCtrl.text = user.major;
      _avatar = user.avatar;
      _gender = user.genderText.isEmpty ? '' : user.genderText;
      _zodiacSign = user.zodiacSign.isEmpty ? '' : user.zodiacSign;
      _mbti = user.mbti.isEmpty ? '' : user.mbti;
      _education = user.education.isEmpty ? '' : user.education;
      _interests.addAll(user.interests);
      _initialized = true;
    }
  }

  void _addInterest() {
    final t = _newInterestCtrl.text.trim();
    if (t.isEmpty) return;
    if (t.length > 8) {
      ref.read(toastControllerProvider).show('单个兴趣最长 8 个字');
      return;
    }
    if (_interests.length >= 5) {
      ref.read(toastControllerProvider).show('最多 5 个兴趣');
      return;
    }
    if (_interests.contains(t)) {
      ref.read(toastControllerProvider).show('该兴趣已添加');
      return;
    }
    setState(() {
      _interests.add(t);
      _newInterestCtrl.clear();
    });
  }

  void _removeInterest(int i) {
    setState(() => _interests.removeAt(i));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _submitting = true);
    try {
      final updated = await ref
          .read(userRepositoryProvider)
          .update(
            user.userId,
            nickname: _nicknameCtrl.text.trim(),
            avatar: _avatar,
            bio: _bioCtrl.text.trim(),
            location: _locationCtrl.text.trim(),
            gender: _gender ?? '',
            zodiacSign: _zodiacSign ?? '',
            mbti: _mbti ?? '',
            education: _education ?? '',
            major: _majorCtrl.text.trim(),
            interests: _interests,
          );
      await ref.read(authControllerProvider.notifier).updateUser(updated);
      if (!mounted) return;
      ref
          .read(toastControllerProvider)
          .success(context.l10n.userProfileUpdated);
      ref.invalidate(userProfileProvider(updated.userId));
      context.pop();
    } catch (e) {
      ref.read(toastControllerProvider).error(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureInit();
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.userEditProfile),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.commonSave),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        Avatar(url: _avatar, size: 96),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).scaffoldBackgroundColor,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _nicknameCtrl,
                  decoration: InputDecoration(
                    labelText: l.authNicknameLabel,
                    hintText: l.authNicknameHint,
                  ),
                  maxLength: 20,
                  validator: Validators.nickname,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _bioCtrl,
                  decoration: InputDecoration(
                    labelText: l.authBioLabel,
                    hintText: l.authBioHint,
                  ),
                  maxLength: 200,
                  maxLines: 3,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _locationCtrl,
                  decoration: InputDecoration(
                    labelText: l.authLocationLabel,
                    hintText: l.authLocationHint,
                  ),
                  maxLength: 30,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('个性标签', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  value: _gender ?? '',
                  decoration: const InputDecoration(labelText: '性别'),
                  items: _genderOptions
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v.isEmpty ? '暂不设置' : v),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _gender = v ?? ''),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  value: _zodiacSign ?? '',
                  decoration: const InputDecoration(labelText: '星座'),
                  items: _zodiacOptions
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v.isEmpty ? '暂不设置' : v),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _zodiacSign = v ?? ''),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  value: _mbti ?? '',
                  decoration: const InputDecoration(labelText: 'MBTI'),
                  items: _mbtiOptions
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v.isEmpty ? '暂不设置' : v),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _mbti = v ?? ''),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  value: _education ?? '',
                  decoration: const InputDecoration(labelText: '学历'),
                  items: _educationOptions
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v.isEmpty ? '暂不设置' : v),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _education = v ?? ''),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _majorCtrl,
                  decoration: const InputDecoration(
                    labelText: '专业',
                    hintText: '请输入专业',
                  ),
                  maxLength: 11,
                ),
                const SizedBox(height: AppSpacing.md),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('兴趣爱好'),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (_interests.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (var i = 0; i < _interests.length; i++)
                          Chip(
                            label: Text(_interests[i]),
                            onDeleted: () => _removeInterest(i),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _newInterestCtrl,
                        decoration: const InputDecoration(
                          hintText: '输入兴趣爱好后点击添加',
                          isDense: true,
                        ),
                        maxLength: 8,
                        onFieldSubmitted: (_) => _addInterest(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: _addInterest,
                      child: const Text('添加'),
                    ),
                  ],
                ),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '最长 8 个字，最多 5 个',
                      style: TextStyle(fontSize: AppTextSize.caption),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final l = context.l10n;
    final picker = ImagePicker();
    final XFile? file;
    try {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 512,
        maxHeight: 512,
      );
    } on Exception catch (_) {
      if (mounted) {
        ref.read(toastControllerProvider).error(l.commonOperationFailed);
      }
      return;
    }
    if (file == null) return; 

    final uploadApi = ref.read(uploadApiProvider);
    final toast = ref.read(toastControllerProvider);

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final url = await uploadApi.uploadImage(File(file.path));
      final cleaned = cleanString(url);
      if (mounted) Navigator.of(context).pop(); 
      setState(() => _avatar = cleaned);
      ref.read(toastControllerProvider).success(l.userProfileUpdated);
    } catch (_) {
      if (mounted) Navigator.of(context).pop(); 
      toast.error(l.commonOperationFailed);
    }
  }
}
