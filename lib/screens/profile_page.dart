import 'package:flutter/material.dart';
import 'package:speechtotext/screens/auth_service.dart';
import 'package:speechtotext/screens/edit_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AuthService _authService = AuthService();
  bool _remindersOn = true;
  bool _eventsOn = false;

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    const themeColor = Color(0xFF2573A6); // Define theme color for reuse

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // --- User Avatar with Edit Icon ---
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage:
                  user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  child: user?.photoURL == null
                      ? Icon(Icons.person, size: 50, color: Colors.grey.shade400)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: themeColor,
                    child: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white, size: 18),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const EditProfilePage(),
                          ),
                        );
                        setState(() {});
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              user?.displayName ?? 'User Name',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              user?.email ?? 'user.email@example.com',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              'UID: ${user?.uid ?? 'N/A'}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 32),

            // --- Settings Options ---
            _buildSettingsTile(
              icon: Icons.timer_outlined,
              title: 'Reminders',
              value: _remindersOn,
              onChanged: (value) {
                setState(() {
                  _remindersOn = value;
                });
              },
            ),
            const SizedBox(height: 12),
            _buildSettingsTile(
              icon: Icons.event_note,
              title: 'All Events',
              value: _eventsOn,
              onChanged: (value) {
                setState(() {
                  _eventsOn = value;
                });
              },
            ),
            const SizedBox(height: 40),

            // ## MODIFIED BUTTON ##
            // The Sign Out button is now an OutlinedButton with the theme color.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await _authService.signOut();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: themeColor, // Blue text
                  side: const BorderSide(color: themeColor, width: 2), // Blue border
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Sign Out',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Card(
      color: const Color(0xFF2573A6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.white),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: Colors.white.withOpacity(0.5),
        ),
      ),
    );
  }
}