import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:speechtotext/screens/history.dart';

class TaskDetailPage extends StatefulWidget {
  final String taskId;

  const TaskDetailPage({Key? key, required this.taskId}) : super(key: key);

  @override
  _TaskDetailPageState createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  late Future<Task?> _taskFuture;

  @override
  void initState() {
    super.initState();
    _taskFuture = _fetchTask();
  }

  Future<Task?> _fetchTask() async {
    try {
      // Check the main tasks collection first
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('Users_Tasks').doc(widget.taskId).get();

      // If not found, check the deleted tasks collection
      if (!doc.exists) {
        doc = await FirebaseFirestore.instance.collection('Users_Deleted_Tasks').doc(widget.taskId).get();
      }

      if (doc.exists) {
        return Task.fromFirestore(doc);
      }
    } catch (e) {
      print("Error fetching task: $e");
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // MODIFIED: AppBar now uses the app's theme
      appBar: AppBar(
        title: const Text('Task Details'),
      ),
      body: FutureBuilder<Task?>(
        future: _taskFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(
              child: Text(
                'Task not found.',
                style: TextStyle(fontSize: 18, color: Colors.black54),
              ),
            );
          }

          final task = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (task.description.isNotEmpty)
                  Text(
                    task.description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black87, height: 1.5),
                  ),
                const SizedBox(height: 24),
                Card(
                  elevation: 1,
                  color: Colors.grey.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildDetailRow('Status', task.status, Icons.sync_problem_rounded),
                        _buildDetailRow('Priority', task.priority, Icons.flag_rounded),
                        _buildDetailRow('Category', task.category, Icons.category_rounded),
                        const Divider(height: 32),
                        _buildDetailRow('Start Date', task.startDate != null ? DateFormat('EEE, MMM d, yyyy').format(task.startDate!) : 'N/A', Icons.calendar_today_rounded),
                        _buildDetailRow('Start Time', task.startTime, Icons.access_time_filled_rounded),
                        const SizedBox(height: 16),
                        _buildDetailRow('End Date', task.endDate != null ? DateFormat('EEE, MMM d, yyyy').format(task.endDate!) : 'N/A', Icons.calendar_today_rounded),
                        _buildDetailRow('End Time', task.endTime, Icons.access_time_rounded),
                      ],
                    ),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[600], size: 20),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(color: Colors.black, fontSize: 16),
          ),
        ],
      ),
    );
  }
}