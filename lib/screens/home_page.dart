import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speechtotext/screens/auth_service.dart';
import 'package:speechtotext/screens/task_list_page.dart';
import 'package:speechtotext/screens/speech_to_text.dart';

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
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TaskFormPage()),
              ).then((_) => setState(() {}));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              const Text('Task Status',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              FutureBuilder<Map<String, int>>(
                future: _fetchTaskCounts(),
                builder: (context, snapshot) {
                  final Map<String, int>? counts = snapshot.data;

                  final cardData = [
                    StatusCardInfo(title: 'To Do', icon: Icons.pending_actions, color: const Color(0xFF8BA9D8), count: counts?['To Do']),
                    StatusCardInfo(title: 'In Progress', icon: Icons.sync, color: const Color(0xFF8A7B94), count: counts?['In Progress']),
                    StatusCardInfo(title: 'Done', icon: Icons.check_circle, color: const Color(0xFF99B89A), count: counts?['Done']),
                    StatusCardInfo(title: 'Deleted', icon: Icons.delete_forever, color: const Color(0xFFD48E8E), count: counts?['Deleted'], isArchived: true),
                  ];

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 4,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.8,
                    ),
                    itemBuilder: (context, index) {
                      return InteractiveStatusCard(
                        cardInfo: cardData[index],
                        onTap: () {
                          if (counts != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TaskListPage(
                                  status: cardData[index].title,
                                  color: cardData[index].color,
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

class InteractiveStatusCard extends StatefulWidget {
  final StatusCardInfo cardInfo;
  final VoidCallback onTap;

  const InteractiveStatusCard({
    Key? key,
    required this.cardInfo,
    required this.onTap,
  }) : super(key: key);

  @override
  State<InteractiveStatusCard> createState() => _InteractiveStatusCardState();
}

class _InteractiveStatusCardState extends State<InteractiveStatusCard> {
  bool _isPressed = false;

  void _onPress(bool isPressed) {
    setState(() {
      _isPressed = isPressed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.cardInfo.count;

    return GestureDetector(
      onTapDown: (_) => _onPress(true),
      onTapUp: (_) {
        _onPress(false);
        widget.onTap();
      },
      onTapCancel: () => _onPress(false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: widget.cardInfo.color,
            borderRadius: BorderRadius.circular(20.0),
            boxShadow: [
              BoxShadow(
                color: widget.cardInfo.color.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.cardInfo.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Icon(widget.cardInfo.icon, color: Colors.white.withOpacity(0.8), size: 22),
                ],
              ),
              if (count != null)
                Text(
                  '$count Tasks',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                )
              else
                SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.8)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
