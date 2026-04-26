import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'app_snackbar.dart';

void setupNotificationHandlers(BuildContext context) {
  // パターン1: フォアグラウンド中に届いた通知（flutter_local_notificationsで表示）
  FirebaseMessaging.onMessage.listen((message) {
    final notification = message.notification;
    if (notification == null || !context.mounted) return;

    showAppSnackBar(
      context,
      notification.body ?? '',
      title: notification.title,
    );
  });

  // パターン2: バックグラウンド中の通知をタップした
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    if (!context.mounted) return;
    _navigateFromNotification(context, message.data);
  });

  // パターン3: アプリ終了状態から通知タップで起動した
  FirebaseMessaging.instance.getInitialMessage().then((message) {
    if (message == null || !context.mounted) return;
    _navigateFromNotification(context, message.data);
  });
}

void _navigateFromNotification(BuildContext context, Map<String, dynamic> data) {
  switch (data['type']) {
    case 'join_approved':
    case 'slot_confirmed':
      context.go('/home');
    default:
      context.go('/home');
  }
}
