import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speechtotext/screens/auth_service.dart';
import 'package:speechtotext/screens/task_list_page.dart';

// This custom widget remains the same.
class GradientCircularLoader extends StatefulWidget {
  final double size;
  final double strokeWidth;
  final Color color;

  const GradientCircularLoader({
    Key? key,
    this.size = 16.0,
    this.strokeWidth = 2.0,
    required this.color,
  }) : super(key: key);

  @override
  _GradientCircularLoaderState createState() => _GradientCircularLoaderState();
}

class _GradientCircularLoaderState extends State<GradientCircularLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RotationTransition(
        turns: _controller,
        child: CustomPaint(
          painter: _GradientPainter(
            strokeWidth: widget.strokeWidth,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _GradientPainter extends CustomPainter {
  final double strokeWidth;
  final Color color;

  _GradientPainter({required this.strokeWidth, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: size.width / 2);
    const sweepAngle = math.pi * 1.75;
    const startAngle = -math.pi / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        colors: [
          color.withOpacity(0.0),
          color,
        ],
        startAngle: 0.0,
        endAngle: sweepAngle,
        stops: const [0.0, 0.7],
      ).createShader(rect);

    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
  // ## MODIFIED ##: Added a state variable to hold the future.
  late Future<Map<String, int>> _taskCountsFuture;

  // ## MODIFIED ##: Initialize the future in initState.
  @override
  void initState() {
    super.initState();
    _taskCountsFuture = _fetchTaskCounts();
  }

  // ## MODIFIED ##: Created a dedicated method to refresh the counts.
  void _refreshTaskCounts() {
    setState(() {
      _taskCountsFuture = _fetchTaskCounts();
    });
  }

  Future<Map<String, int>> _fetchTaskCounts() async {
    // This delay is for demonstration; you can remove it if not needed.
    await Future.delayed(const Duration(milliseconds: 500));
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
        // ## MODIFIED ##: onRefresh now calls the new refresh method.
        onRefresh: () async => _refreshTaskCounts(),
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
                // ## MODIFIED ##: The FutureBuilder now uses the state variable.
                future: _taskCountsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
                    // Show placeholders while waiting for the initial load
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('Could not fetch tasks.'),
                    );
                  }
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
                          // Navigate and then refresh the counts when the user returns.
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TaskListPage(
                                status: cardData[index].title,
                                isArchived: cardData[index].isArchived,
                              ),
                            ),
                            // ## MODIFIED ##: The .then() callback now calls the refresh method.
                          ).then((_) => _refreshTaskCounts());
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
                  (count != null)
                      ? Text(
                    '$count Tasks',
                    style: TextStyle(
                      color: cardForegroundColor.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  )
                      : GradientCircularLoader(color: cardForegroundColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}