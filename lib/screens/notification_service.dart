import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  // A static instance of the notifications plugin
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  /// Initializes the notification service.
  /// This should be called once in main.dart when the app starts.
  static void init() {
    // Settings for Android
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher'); // Uses the default app icon

    // Settings for iOS
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // Initialize the plugin with the settings
    _notificationsPlugin.initialize(initializationSettings);
  }

  /// Schedules a one-time notification for when a task becomes overdue.
  static Future<void> scheduleOverdueNotification({
    required String taskId,
    required String title,
    required String description,
    required DateTime endDate,
    required String endTime,
  }) async {
    // If no end time is provided, we cannot schedule the notification.
    if (endTime.isEmpty) {
      return;
    }

    try {
      final tz.TZDateTime scheduledDate = _createScheduledDateTime(endDate, endTime);

      // Use the task's ID hash code as a unique ID for the notification.
      // This allows us to find and cancel it later.
      final int notificationId = taskId.hashCode;

      // Do not schedule notifications for dates in the past.
      if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
        return;
      }

      await _notificationsPlugin.zonedSchedule(
        notificationId,
        'Task Overdue: $title',
        description.isNotEmpty ? description : 'This task is now overdue. Please review it.',
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'overdue_tasks_channel',
            'Overdue Tasks',
            channelDescription: 'Notifications for tasks that have passed their due date.',
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      print('Error scheduling notification: $e');
    }
  }

  /// Cancels a previously scheduled notification using the task's ID.
  static Future<void> cancelNotification(String taskId) async {
    try {
      final int notificationId = taskId.hashCode;
      await _notificationsPlugin.cancel(notificationId);
    } catch (e) {
      print('Error canceling notification: $e');
    }
  }

  /// A helper function to combine a date and a time string (e.g., "5:30 PM")
  /// into a timezone-aware TZDateTime object.
  static tz.TZDateTime _createScheduledDateTime(DateTime date, String timeString) {
    final TimeOfDay time = TimeOfDay.fromDateTime(DateFormat.jm().parse(timeString));
    final DateTime combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    return tz.TZDateTime.from(combined, tz.local);
  }
}