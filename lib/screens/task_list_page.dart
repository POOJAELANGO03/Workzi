import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:speechtotext/screens/auth_service.dart';
import 'package:speechtotext/screens/notification_service.dart';
import 'history.dart';

class TaskListPage extends StatelessWidget {
  final String status;
  final bool isArchived;

  const TaskListPage({
    Key? key,
    required this.status,
    this.isArchived = false,
  }) : super(key: key);

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Colors.red.shade400;
      case 'medium':
        return Colors.orange.shade400;
      case 'low':
        return Colors.blue.shade400;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService();
    final user = authService.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tasks')),
        body: const Center(child: Text("Please log in.")),
      );
    }

    final collectionPath = isArchived ? 'Users_Deleted_Tasks' : 'Users_Tasks';
    Query query = FirebaseFirestore.instance
        .collection(collectionPath)
        .where('uid', isEqualTo: user.uid);

    if (!isArchived) {
      query = query.where('status', isEqualTo: status);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isArchived ? 'Deleted Tasks' : '$status Tasks'),
        actions: isArchived
            ? [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () => _clearAllDeletedTasks(context),
            tooltip: 'Clear All',
          ),
        ]
            : [],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            final message = isArchived
                ? 'No tasks in your history.'
                : 'No tasks found for "$status".';
            return Center(
              child: Text(message,
                  style: const TextStyle(color: Colors.black54, fontSize: 16)),
            );
          }
          final tasks =
          snapshot.data!.docs.map((doc) => Task.fromFirestore(doc)).toList();
          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              return _buildExpandableTaskCard(context, tasks[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildExpandableTaskCard(BuildContext context, Task task) {
    final priorityColor = _getPriorityColor(task.priority);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          border: Border(
            left: BorderSide(color: priorityColor, width: 5),
          ),
        ),
        child: ExpansionTile(
          title: Text(task.title,
              style:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: Text(
            task.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[600]),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Divider(height: 24),
            _buildDetailRow('Category', task.category),
            _buildDetailRow('Priority', task.priority),
            _buildDetailRow('Start Time', task.startTime),
            _buildDetailRow('End Time', task.endTime),
            if (task.startDate != null)
              _buildDetailRow(
                  'Start Date', DateFormat('dd/MM/yyyy').format(task.startDate!)),
            if (task.endDate != null)
              _buildDetailRow(
                  'End Date', DateFormat('dd/MM/yyyy').format(task.endDate!)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (task.status == 'To Do')
                  _buildStatusButton(
                      context, task.id, 'In Progress', Colors.blue),
                if (task.status == 'In Progress')
                  _buildStatusButton(context, task.id, 'Done', Colors.green),
                const SizedBox(width: 8),
                _buildDeleteButton(context, task.id),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildStatusButton(BuildContext context, String taskId, String newStatus, Color btnColor) {
    return ElevatedButton(
      onPressed: () => _updateTaskStatus(context, taskId, newStatus),
      style: ElevatedButton.styleFrom(
        backgroundColor: btnColor,
        foregroundColor: Colors.white,
      ),
      child: Text(newStatus),
    );
  }

  Widget _buildDeleteButton(BuildContext context, String taskId) {
    return TextButton(
      onPressed: () => _deleteAndArchiveTask(context, taskId),
      style: TextButton.styleFrom(
        foregroundColor: Colors.red,
      ),
      child: const Text('Delete'),
    );
  }

  Future<void> _deleteAndArchiveTask(BuildContext context, String taskId) async {
    // Cancel any pending notifications for this task first
    await NotificationService.cancelNotification(taskId);

    final taskRef = FirebaseFirestore.instance.collection('Users_Tasks').doc(taskId);
    try {
      final doc = await taskRef.get();
      if (doc.exists) {
        await FirebaseFirestore.instance.collection('Users_Deleted_Tasks').doc(taskId).set(doc.data()!);
        await taskRef.delete();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task Deleted and Archived')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete task.')));
      }
    }
  }

  Future<void> _updateTaskStatus(BuildContext context, String taskId, String newStatus) async {
    // If the task is being marked as 'Done', cancel its notifications
    if (newStatus == 'Done') {
      await NotificationService.cancelNotification(taskId);
    }

    await FirebaseFirestore.instance.collection('Users_Tasks').doc(taskId).update({'status': newStatus});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Task moved to "$newStatus"')));
    }
  }

  Future<void> _clearAllDeletedTasks(BuildContext context) async {
    final user = AuthService().currentUser;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance.collection('Users_Deleted_Tasks').where('uid', isEqualTo: user.uid).get();
      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All deleted tasks cleared')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to clear deleted tasks.')));
      }
    }
  }
}