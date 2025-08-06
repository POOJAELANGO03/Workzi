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

// Main page structure remains the same.
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
    await Future.delayed(const Duration(seconds: 2));
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
                          if (counts != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
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

// ## MODIFIED WIDGET ##
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
        padding: const EdgeInsets.all(12.0), // A single padding for the container
        decoration: BoxDecoration(
          color: cardInfo.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: cardInfo.color.withOpacity(0.3)),
        ),
        // The ListTile is replaced with a Row/Column for better alignment control.
        child: Row(
          children: [
            Icon(cardInfo.icon, color: cardInfo.color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cardInfo.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  // This part conditionally shows the text or the loader.
                  (count != null)
                      ? Text(
                    '$count Tasks',
                    style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 14),
                  )
                      : GradientCircularLoader(color: cardInfo.color),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}