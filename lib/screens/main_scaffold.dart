import 'package:flutter/material.dart';
import 'package:speechtotext/screens/home_page.dart';
import 'package:speechtotext/screens/calendar_page.dart';
import 'package:speechtotext/screens/history.dart'; // Import the HistoryPage
import 'package:speechtotext/screens/profile_page.dart';
import 'package:speechtotext/screens/speech_to_text.dart'; // This is your TaskFormPage

class MainScaffold extends StatefulWidget {
  const MainScaffold({Key? key}) : super(key: key);

  @override
  _MainScaffoldState createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;

  // Updated the list of pages to include History
  static const List<Widget> _widgetOptions = <Widget>[
    HomePage(),     // Index 0: Home
    CalendarPage(), // Index 1: Calendar
    HistoryPage(),  // Index 2: History
    ProfilePage(),  // Index 3: Profile
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to the TaskFormPage when the button is pressed
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TaskFormPage()),
          );
        },
        child: const Icon(Icons.add),
        backgroundColor: Colors.blueAccent,
        elevation: 2.0,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      // Using a BottomAppBar for the notched look
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          // This layout has been updated to include the History icon
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            // Home Button
            _buildNavItem(icon: Icons.home, index: 0, tooltip: 'Home'),
            // Calendar Button
            _buildNavItem(icon: Icons.calendar_today, index: 1, tooltip: 'Calendar'),
            // This is the empty space for the floating action button
            const SizedBox(width: 40),
            // History Button
            _buildNavItem(icon: Icons.history, index: 2, tooltip: 'History'),
            // Profile Button
            _buildNavItem(icon: Icons.person, index: 3, tooltip: 'Profile'),
          ],
        ),
      ),
    );
  }

  // Helper widget to build each navigation item to reduce code repetition
  Widget _buildNavItem({
    required IconData icon,
    required int index,
    required String tooltip,
  }) {
    return IconButton(
      icon: Icon(
        icon,
        color: _selectedIndex == index ? Colors.black : Colors.blueGrey,
      ),
      onPressed: () => _onItemTapped(index),
      tooltip: tooltip,
    );
  }
}
