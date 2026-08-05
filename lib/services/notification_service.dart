import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

/// Handles FCM push notifications and local notifications.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background messages
  debugPrint('Background message: ${message.notification?.title}');
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();

  static const _channelId = 'cut_safety_alerts';
  static const _channelName = 'CUT Safety Alerts';

  Future<void> init() async {
    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    // Local notifications setup
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Create notification channel (Android 8+)
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Safety alerts and updates from your CUT campus',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        ));

    // Handle foreground FCM messages
    FirebaseMessaging.onMessage.listen((msg) {
      final n = msg.notification;
      if (n != null) showLocal(title: n.title ?? '', body: n.body ?? '');
    });

    // Subscribe to campus-wide alerts topic
    await _fcm.subscribeToTopic('all_alerts');
  }

  /// Subscribe to a group's notification topic.
  Future<void> subscribeToGroup(String groupId) =>
      _fcm.subscribeToTopic('group_$groupId');

  Future<void> unsubscribeFromGroup(String groupId) =>
      _fcm.unsubscribeFromTopic('group_$groupId');

  /// Show an immediate local notification.
  Future<void> showLocal({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'CUT Safety Alerts',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  /// Show an SOS notification to all group members.
  Future<void> showSOSNotification(String senderName, String location) {
    return showLocal(
      title: '🚨 SOS — $senderName needs help!',
      body: 'Location: $location. Tap to view.',
    );
  }

  Future<String?> getToken() => _fcm.getToken();
}
