// lib/screens/history.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:speechtotext/screens/auth_service.dart';

// Data Model for a Task, fetched from Firestore
class Task {
  final String id;
  final String title;
  final String description;
  final String category;
  final String priority;
  final String startTime;
  final String endTime;
  final DateTime? startDate;
  final DateTime? endDate;
  final Timestamp createdAt;
  final String status;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.priority,
    required this.startTime,
    required this.endTime,
    this.startDate,
    this.endDate,
    required this.createdAt,
    required this.status,
  });

  factory Task.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Task(
      id: doc.id,
      title: data['title'] ?? 'No Title',
      description: data['description'] ?? '',
      category: data['category'] ?? 'General',
      priority: data['priority'] ?? 'Low',
      startTime: data['startTime'] ?? '',
      endTime: data['endTime'] ?? '',
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      createdAt: data['createdAt'] ?? Timestamp.now(),
      status: data['status'] ?? 'To Do',
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final AuthService _authService = AuthService();

  Map<String, List<Task>> _groupTasks(List<Task> tasks) {
    final Map<String, List<Task>> groupedTasks = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);

    for (var task in tasks) {
      final taskDate = task.createdAt.toDate();
      final taskDay = DateTime(taskDate.year, taskDate.month, taskDate.day);
      String key;

      if (isSameDay(taskDay, today)) {
        key = 'Today';
      } else if (isSameDay(taskDay, yesterday)) {
        key = 'Yesterday';
      } else {
        key = DateFormat('MMMM d, yyyy').format(taskDate);
      }

      if (groupedTasks[key] == null) {
        groupedTasks[key] = [];
      }
      groupedTasks[key]!.add(task);
    }
    return groupedTasks;
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _deleteTask(String taskId) async {
    try {
      final taskRef = FirebaseFirestore.instance.collection('Users_Tasks').doc(taskId);
      final doc = await taskRef.get();
      if (doc.exists) {
        await FirebaseFirestore.instance.collection('Users_Deleted_Tasks').doc(taskId).set(doc.data()!);
        await taskRef.delete();
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task deleted and archived successfully!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete task.')));
    }
  }

  Future<void> _clearAllTasks(BuildContext context) async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users_Tasks')
          .where('uid', isEqualTo: user.uid)
          .get();
      for (var doc in snapshot.docs) {
        await FirebaseFirestore.instance.collection('Users_Deleted_Tasks').doc(doc.id).set(doc.data()!);
        await FirebaseFirestore.instance.collection('Users_Tasks').doc(doc.id).delete();
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All tasks cleared and archived')));
      Navigator.pop(context); // Return to HomePage to refresh
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to clear tasks.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    if (user == null) {
      return const Center(child: Text("Please log in to see your history."));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task History'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white),
            onPressed: () => _clearAllTasks(context),
            tooltip: 'Clear All',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Users_Tasks')
            .where('uid', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Could not load tasks. Please check your connection.',
                style: TextStyle(fontSize: 18, color: Colors.red),
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No tasks found.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          final tasks = snapshot.data!.docs
              .map((doc) => Task.fromFirestore(doc))
              .toList();

          final groupedTasks = _groupTasks(tasks);
          final dateKeys = groupedTasks.keys.toList();

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: dateKeys.length,
            itemBuilder: (context, index) {
              final dateKey = dateKeys[index];
              final tasksForDay = groupedTasks[dateKey]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
                    child: Text(
                      dateKey,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: tasksForDay.length,
                    itemBuilder: (context, taskIndex) {
                      return TaskExpansionTile(
                        task: tasksForDay[taskIndex],
                        onDelete: () => _deleteTask(tasksForDay[taskIndex].id),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class TaskExpansionTile extends StatelessWidget {
  final Task task;
  final VoidCallback onDelete;

  const TaskExpansionTile({Key? key, required this.task, required this.onDelete}) : super(key: key);

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Colors.red.shade400;
      case 'medium':
        return Colors.blue.shade400;
      case 'low':
        return Colors.green.shade400;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final priorityColor = _getPriorityColor(task.priority);
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: Icon(Icons.check_circle, color: priorityColor),
        title: Text(
          task.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Priority: ${task.priority} | Status: ${task.status}',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 16),
              if (task.description.isNotEmpty) ...[
                const Text(
                  'Description',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(task.description),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailColumn('Category', task.category),
                  if (task.startTime.isNotEmpty)
                    _buildDetailColumn('Start Time', task.startTime),
                  if (task.endTime.isNotEmpty)
                    _buildDetailColumn('End Time', task.endTime),
                  _buildDetailColumn('Created', DateFormat.jm().format(task.createdAt.toDate())),
                ],
              ),
              if (task.startDate != null)
                _buildDetailColumn('Start Date', DateFormat('dd/MM/yyyy').format(task.startDate!)),
              if (task.endDate != null)
                _buildDetailColumn('End Date', DateFormat('dd/MM/yyyy').format(task.endDate!)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: onDelete,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailColumn(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(value),
      ],
    );
  }
}