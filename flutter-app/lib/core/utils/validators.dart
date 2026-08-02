/// 表单校验工具：返回错误文案，通过则返回 null。
class Validators {
  const Validators._();

  static String? userId(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '请输入瓜呱号';
    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(v)) {
      return '瓜呱号为 3-20 位字母、数字或下划线';
    }
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return '请输入密码';
    if (v.length < 6 || v.length > 20) return '密码长度需为 6-20 位';
    return null;
  }

  static String? nickname(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '请输入昵称';
    if (v.length > 20) return '昵称最长 20 位';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    final v = value ?? '';
    if (v.isEmpty) return '请再次输入密码';
    if (v != original) return '两次输入的密码不一致';
    return null;
  }

  static String? required(String? value, {String label = '该项'}) {
    if (value == null || value.trim().isEmpty) return '$label不能为空';
    return null;
  }
}
