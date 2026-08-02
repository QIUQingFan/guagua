/// 环境变量
class Env {
  const Env._();

  /// 后端 API 基础地址
  /// 默认指向 Android 模拟器宿主机
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3001/api',
  );

  /// Socket.IO 服务地址。
  static const socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );

  /// 当前环境标识：dev / staging / prod。
  static const env = String.fromEnvironment('ENV', defaultValue: 'dev');

  static bool get isProd => env == 'prod';
  static bool get isStaging => env == 'staging';
  static bool get isDev => env == 'dev';
}
