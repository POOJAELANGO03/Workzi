import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:speechtotext/screens/auth_service.dart';
import 'history.dart';

class TaskListPage extends StatelessWidget {
  final String status;
  final Color color;
  final bool isArchived;

  const TaskListPage({
    Key? key,
    required this.status,
    required this.color,
    this.isArchived = false,
  }) : super(key: key);

  Future<void> _deleteAndArchiveTask(BuildContext context, String taskId) async {
    final taskRef = FirebaseFirestore.instance.collection('Users_Tasks').doc(taskId);
    try {
      final doc = await taskRef.get();
      if (doc.exists) {
        await FirebaseFirestore.instance.collection('Users_Deleted_Tasks').doc(taskId).set(doc.data()!);
        await taskRef.delete();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task Deleted and Archived')));
        Navigator.pop(context); // Refresh HomePage
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete task.')));
      }
    }
  }

  Future<void> _updateTaskStatus(BuildContext context, String taskId, String newStatus) async {
    await FirebaseFirestore.instance.collection('Users_Tasks').doc(taskId).update({'status': newStatus});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Task moved to "$newStatus"')));
    }
  }

  Future<void> _clearAllDeletedTasks(BuildContext context) async {
    final user = AuthService().currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users_Deleted_Tasks')
          .where('uid', isEqualTo: user.uid)
          .get();
      for (var doc in snapshot.docs) {
        await FirebaseFirestore.instance.collection('Users_Deleted_Tasks').doc(doc.id).delete();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All deleted tasks cleared')));
        Navigator.pop(context); // Return to HomePage to refresh
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to clear tasks.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService();
    final user = authService.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Please log in.")));
    }

    final collectionPath = isArchived ? 'Users_Deleted_Tasks' : 'Users_Tasks';
    Query query = FirebaseFirestore.instance.collection(collectionPath).where('uid', isEqualTo: user.uid);

    if (!isArchived) {
      query = query.where('status', isEqualTo: status);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('$status Tasks'),
        centerTitle: true,
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: isArchived
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: Colors.white),
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
            return Center(child: Text('No tasks found for "$status".'));
          }
          final tasks = snapshot.data!.docs.map((doc) => Task.fromFirestore(doc)).toList();
          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
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
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12.0),
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: Colors.white,
          collapsedIconColor: Colors.white,
          textColor: Colors.white,
          collapsedTextColor: Colors.white,
          title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          subtitle: Text(task.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.8))),
          children: [
            if (!isArchived)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: Colors.white54, height: 24),
                    const Text('Details:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    _buildDetailRow('Category', task.category),
                    _buildDetailRow('Priority', task.priority),
                    _buildDetailRow('Start Time', task.startTime),
                    _buildDetailRow('End Time', task.endTime),
                    if (task.startDate != null)
                      _buildDetailRow('Start Date', DateFormat('dd/MM/yyyy').format(task.startDate!)),
                    if (task.endDate != null)
                      _buildDetailRow('End Date', DateFormat('dd/MM/yyyy').format(task.endDate!)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (task.status == 'To Do')
                          _buildStatusButton(context, task.id, 'In Progress', Colors.blue),
                        if (task.status == 'In Progress')
                          _buildStatusButton(context, task.id, 'Done', Colors.green),
                        _buildDeleteButton(context, task.id),
                      ],
                    ),
                  ],
                ),
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
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
          Text(value, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildStatusButton(BuildContext context, String taskId, String newStatus, Color btnColor) {
    return TextButton(
      onPressed: () => _updateTaskStatus(context, taskId, newStatus),
      style: TextButton.styleFrom(
        backgroundColor: btnColor.withOpacity(0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(newStatus, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDeleteButton(BuildContext context, String taskId) {
    return TextButton(
      onPressed: () => _deleteAndArchiveTask(context, taskId),
      style: TextButton.styleFrom(
        backgroundColor: Colors.redAccent.withOpacity(0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}