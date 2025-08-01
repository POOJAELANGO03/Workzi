import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speechtotext/screens/auth_service.dart';
import 'package:speechtotext/screens/task_list_page.dart';

class StatusCardInfo {
  final String title;
  final IconData icon;
  final Color color;
  final int? count;
  final bool isArchived;

  StatusCardInfo({
    required this.title,
    required this.icon,
    required this.color,
    this.count,
    this.isArchived = false,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthService _authService = AuthService();

  Future<Map<String, int>> _fetchTaskCounts() async {
    final user = _authService.currentUser;
    if (user == null) return {};

    final activeTasksSnapshot = await FirebaseFirestore.instance
        .collection('Users_Tasks')
        .where('uid', isEqualTo: user.uid)
        .get();

    final deletedTasksSnapshot = await FirebaseFirestore.instance
        .collection('Users_Deleted_Tasks')
        .where('uid', isEqualTo: user.uid)
        .get();

    final counts = {'To Do': 0, 'In Progress': 0, 'Done': 0, 'Deleted': 0};

    for (var doc in activeTasksSnapshot.docs) {
      final status = doc.data()['status'] as String? ?? 'To Do';
      if (counts.containsKey(status)) {
        counts[status] = counts[status]! + 1;
      }
    }
    counts['Deleted'] = deletedTasksSnapshot.docs.length;
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: const [],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Task Status',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              FutureBuilder<Map<String, int>>(
                future: _fetchTaskCounts(),
                builder: (context, snapshot) {
                  final Map<String, int>? counts = snapshot.data;

                  final cardData = [
                    StatusCardInfo(title: 'To Do', icon: Icons.pending_actions_rounded, color: Colors.orange, count: counts?['To Do']),
                    StatusCardInfo(title: 'In Progress', icon: Icons.sync_rounded, color: Colors.blue, count: counts?['In Progress']),
                    StatusCardInfo(title: 'Done', icon: Icons.check_circle_rounded, color: Colors.green, count: counts?['Done']),
                    StatusCardInfo(title: 'Deleted', icon: Icons.delete_forever_rounded, color: Colors.red, count: counts?['Deleted'], isArchived: true),
                  ];

                  return GridView.builder(
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
                          if (counts != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                // MODIFIED: Removed the 'color' parameter
                                builder: (context) => TaskListPage(
                                  status: cardData[index].title,
                                  isArchived: cardData[index].isArchived,
                                ),
                              ),
                            ).then((_) => setState(() {}));
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: cardInfo.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: cardInfo.color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(cardInfo.icon, color: cardInfo.color, size: 28),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  cardInfo.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                if (count != null)
                  Text(
                    '$count Tasks',
                    style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 14),
                  )
                else
                  SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(cardInfo.color.withOpacity(0.8)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}