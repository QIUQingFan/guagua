import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 本地推送通知
class LocalNotificationService with WidgetsBindingObserver {
  LocalNotificationService();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _isForeground = true;

  void Function(String payload)? onTapNotification;

  bool get isForeground => _isForeground;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onTap,
    );

    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'guagua_notifications', // channel id
      '瓜呱通知', // channel name
      channelDescription: '赞和收藏、评论、关注等消息通知',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> showIfBackground({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (_isForeground) return;
    await show(id: id, title: title, body: body, payload: payload);
  }

  /// 取消指定通知。
  Future<void> cancel(int id) => _plugin.cancel(id);

  /// 取消所有通知。
  Future<void> cancelAll() => _plugin.cancelAll();

  /// 通知点击处理：调用注入的回调。
  void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    onTapNotification?.call(payload);
  }

  static String encodePayload(Map<String, dynamic> data) => jsonEncode(data);

  static Map<String, dynamic>? decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

final localNotificationServiceProvider = Provider<LocalNotificationService>((
  ref,
) {
  final service = LocalNotificationService();
  ref.onDispose(() => service.cancelAll());
  return service;
});
