import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:speechtotext/screens/home_page.dart';
import 'package:speechtotext/screens/calendar_page.dart';
import 'package:speechtotext/screens/history.dart';
import 'package:speechtotext/screens/profile_page.dart';
import 'package:speechtotext/screens/speech_to_text.dart';
import 'package:speechtotext/screens/task_detail_page.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({Key? key}) : super(key: key);

  @override
  _MainScaffoldState createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  void _initNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TaskDetailPage(taskId: response.payload!),
            ),
          );
        }
      },
    );

    if (Platform.isAndroid) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
      >()
          ?.requestNotificationsPermission();
    }
  }

  static const List<Widget> _widgetOptions = <Widget>[
    HomePage(),
    CalendarPage(),
    HistoryPage(),
    ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // MODIFIED: primaryActionColor now uses your blue theme color
    const Color primaryActionColor = Color(0xFF1976D2);

    return Scaffold(
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TaskFormPage()),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
        backgroundColor: primaryActionColor,
        elevation: 2.0,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        color: const Color(0xFFF6F6F6),
        elevation: 8.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _buildNavItem(icon: Icons.home_rounded, index: 0, tooltip: 'Home'),
            _buildNavItem(icon: Icons.calendar_today_rounded, index: 1, tooltip: 'Calendar'),
            const SizedBox(width: 40),
            _buildNavItem(icon: Icons.history_rounded, index: 2, tooltip: 'History'),
            _buildNavItem(icon: Icons.person_rounded, index: 3, tooltip: 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required int index,
    required String tooltip,
  }) {
    // MODIFIED: activeColor now uses your blue theme color
    const Color activeColor = Color(0xFF1976D2);

    return IconButton(
      icon: Icon(
        icon,
        color: _selectedIndex == index ? activeColor : Colors.grey[600],
        size: 28,
      ),
      onPressed: () => _onItemTapped(index),
      tooltip: tooltip,
    );
  }
}