import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speechtotext/screens/auth_service.dart';
import 'package:speechtotext/screens/task_list_page.dart';
import 'package:speechtotext/screens/task_form_page.dart';

// NOTE: The GradientCircularLoader, _GradientPainter, and StatusCardInfo classes
// at the top of the file remain exactly the same. They have been omitted here for brevity.

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

// ## REWRITTEN STATE ##
// This entire state has been simplified to use real-time streams.
// All manual refresh logic (initState, dispose, didChangeAppLifecycleState, FutureBuilder) has been removed.
class _HomePageState extends State<HomePage> {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    // Handle the case where the user is not logged in.
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: const Center(child: Text("Please log in to view tasks.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: const [],
      ),
      // This StreamBuilder listens for real-time changes in your main tasks collection.
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Users_Tasks')
            .where('uid', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, activeTasksSnapshot) {
          if (activeTasksSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (activeTasksSnapshot.hasError) {
            return const Center(child: Text('Could not load tasks.'));
          }

          // Calculate counts for active tasks
          final counts = {'To Do': 0, 'In Progress': 0, 'Done': 0};
          for (var doc in activeTasksSnapshot.data?.docs ?? []) {
            final status = (doc.data() as Map<String, dynamic>)['status'] as String? ?? 'To Do';
            if (counts.containsKey(status)) {
              counts[status] = counts[status]! + 1;
            }
          }

          // This nested StreamBuilder listens for changes in your deleted tasks collection.
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Users_Deleted_Tasks')
                .where('uid', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, deletedTasksSnapshot) {

              final deletedCount = deletedTasksSnapshot.data?.docs.length ?? 0;

              final cardData = [
                StatusCardInfo(title: 'To Do', icon: Icons.pending_actions_rounded, count: counts['To Do']),
                StatusCardInfo(title: 'In Progress', icon: Icons.sync_rounded, count: counts['In Progress']),
                StatusCardInfo(title: 'Done', icon: Icons.check_circle_rounded, count: counts['Done']),
                StatusCardInfo(title: 'Deleted', icon: Icons.delete_forever_rounded, count: deletedCount, isArchived: true),
              ];

              // The body content is now built inside the streams
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Task Status',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 4,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 2.5,
                      ),
                      itemBuilder: (context, index) {
                        return StatusCard(
                          cardInfo: cardData[index],
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TaskListPage(
                                  status: cardData[index].title,
                                  isArchived: cardData[index].isArchived,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      // The floating action button is handled by your main navigation scaffold,
      // so it is not needed here.
    );
  }
}

class StatusCard extends StatelessWidget {
  final StatusCardInfo cardInfo;
  final VoidCallback onTap;

  const StatusCard({
    Key? key,
    required this.cardInfo,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final count = cardInfo.count;
    const cardBackgroundColor = Color(0xFF2573A6);
    const cardForegroundColor = Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: cardBackgroundColor,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Row(
          children: [
            Icon(cardInfo.icon, color: cardForegroundColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cardInfo.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: cardForegroundColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    // Displaying count directly now, no need for a loader
                    '$count Tasks',
                    style: TextStyle(
                      color: cardForegroundColor.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// NOTE: The StatusCardInfo class definition is assumed to be here, but has been simplified
// in the code above for clarity. Make sure it includes the necessary properties.
class StatusCardInfo {
  final String title;
  final IconData icon;
  final int? count;
  final bool isArchived;

  StatusCardInfo({
    required this.title,
    required this.icon,
    this.count,
    this.isArchived = false,
  });
}