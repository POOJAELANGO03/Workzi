import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class TaskEvent {
  final String id;
  final String title;
  final String description;
  final String category;
  final String priority;
  final String startTime;
  final String endTime;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;
  final bool isGoogleEvent;

  TaskEvent({
    required this.id,
    required this.title,
    this.description = '',
    this.category = 'N/A',
    this.priority = 'N/A',
    this.startTime = 'N/A',
    this.endTime = 'N/A',
    this.startDate,
    this.endDate,
    this.status = 'To Do',
    this.isGoogleEvent = false,
  });

  factory TaskEvent.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return TaskEvent(
      id: doc.id,
      title: data['title'] ?? 'Untitled Task',
      description: data['description'] ?? '',
      category: data['category'] ?? 'N/A',
      priority: data['priority'] ?? 'N/A',
      startTime: data['startTime'] ?? 'N/A',
      endTime: data['endTime'] ?? 'N/A',
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      status: data['status'] ?? 'To Do',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'category': category,
      'priority': priority,
      'startTime': startTime,
      'endTime': endTime,
      'startDate': startDate,
      'endDate': endDate,
      'status': status,
      'uid': FirebaseAuth.instance.currentUser?.uid,
      'createdAt': Timestamp.now(),
    };
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({Key? key}) : super(key: key);

  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late final ValueNotifier<List<TaskEvent>> _selectedEvents;
  final Map<DateTime, List<TaskEvent>> _events = LinkedHashMap(
    equals: isSameDay,
    hashCode: (key) => key.day * 1000000 + key.month * 10000 + key.year,
  );

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isLoading = true;
  String? _errorMessage;

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _selectedEvents = ValueNotifier(_getEventsForDay(_selectedDay!));
    _fetchAllEvents();
  }

  Future<void> _fetchAllEvents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final firestoreTasks = await _fetchFirestoreTasks();
      final googleEvents = await _fetchGoogleCalendarEvents();

      _events.clear();

      firestoreTasks.forEach((date, tasks) {
        if (_events[date] == null) _events[date] = [];
        _events[date]!.addAll(tasks);
      });

      googleEvents.forEach((date, gEvents) {
        if (_events[date] == null) _events[date] = [];
        _events[date]!.addAll(gEvents);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load events. Please try again.';
      });
      print('Error fetching events: $e');
    }

    setState(() {
      _isLoading = false;
      if (mounted && _selectedDay != null) {
        _selectedEvents.value = _getEventsForDay(_selectedDay!);
      }
    });
  }

  Future<Map<DateTime, List<TaskEvent>>> _fetchFirestoreTasks() async {
    final user = _authService.currentUser;
    if (user == null) return {};

    final Map<DateTime, List<TaskEvent>> firestoreEvents = {};
    final snapshot = await FirebaseFirestore.instance
        .collection('Users_Tasks')
        .where('uid', isEqualTo: user.uid)
        .get();

    for (var doc in snapshot.docs) {
      final task = TaskEvent.fromFirestore(doc);
      final eventDate = task.startDate ?? DateTime.now();
      final eventDateUtc =
      DateTime.utc(eventDate.year, eventDate.month, eventDate.day);
      if (firestoreEvents[eventDateUtc] == null) {
        firestoreEvents[eventDateUtc] = [];
      }
      firestoreEvents[eventDateUtc]!.add(task);
    }
    return firestoreEvents;
  }

  Future<Map<DateTime, List<TaskEvent>>> _fetchGoogleCalendarEvents() async {
    final googleSignIn =
    GoogleSignIn(scopes: [calendar.CalendarApi.calendarScope]);
    final googleUser = await googleSignIn.signInSilently();
    if (googleUser == null) {
      print("User not signed in for calendar or needs to grant permission.");
      return {};
    }

    final headers = await googleUser.authHeaders;
    final client = GoogleAuthClient(headers);
    final cal = calendar.CalendarApi(client);
    final eventsResult = await cal.events.list("primary");

    final Map<DateTime, List<TaskEvent>> googleEvents = {};
    if (eventsResult.items != null) {
      for (var event in eventsResult.items!) {
        final startTime =
            event.start?.dateTime?.toUtc() ?? event.start?.date?.toUtc();
        if (startTime != null) {
          final eventDate =
          DateTime.utc(startTime.year, startTime.month, startTime.day);
          final task = TaskEvent(
            id: event.id ?? '',
            title: event.summary ?? 'No Title',
            description: event.description ?? '',
            isGoogleEvent: true,
          );
          if (googleEvents[eventDate] == null) googleEvents[eventDate] = [];
          googleEvents[eventDate]!.add(task);
        }
      }
    }
    return googleEvents;
  }

  Future<void> _updateTaskStatus(String taskId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('Users_Tasks')
          .doc(taskId)
          .update({'status': newStatus});
      await _fetchAllEvents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Task status updated to "$newStatus"')),
        );
      }
    } catch (e) {
      print("Failed to update status: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update status.')),
        );
      }
    }
  }

  Future<void> _deleteTask(String taskId) async {
    try {
      final taskRef =
      FirebaseFirestore.instance.collection('Users_Tasks').doc(taskId);
      final doc = await taskRef.get();
      if (doc.exists) {
        await FirebaseFirestore.instance
            .collection('Users_Deleted_Tasks')
            .doc(taskId)
            .set(doc.data()!);
        await taskRef.delete();
        _fetchAllEvents(); // Refresh calendar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Task Deleted and Archived')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete task.')));
      }
    }
  }

  // ## MODIFIED ##: Dialog reverted to default light theme
  void _showTaskDetailsDialog(TaskEvent event) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
          Text(event.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                if (event.description.isNotEmpty) ...[
                  const Text('Description:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(event.description),
                  const SizedBox(height: 10),
                ],
                if (!event.isGoogleEvent) ...[
                  const Text('Category:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(event.category),
                  const SizedBox(height: 10),
                  const Text('Priority:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(event.priority),
                  const SizedBox(height: 10),
                  const Text('Time:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${event.startTime} - ${event.endTime}'),
                  if (event.startDate != null) ...[
                    const SizedBox(height: 10),
                    const Text('Start Date:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(DateFormat('dd/MM/yyyy').format(event.startDate!)),
                  ],
                  if (event.endDate != null) ...[
                    const SizedBox(height: 10),
                    const Text('End Date:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(DateFormat('dd/MM/yyyy').format(event.endDate!)),
                  ],
                  const Divider(height: 20),
                  const Text('Update Status:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: ['To Do', 'In Progress', 'Done', 'Cancel']
                        .map((status) => ElevatedButton(
                      onPressed: () {
                        if (event.id.isNotEmpty) {
                          Navigator.of(context).pop();
                          _updateTaskStatus(event.id, status);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: event.status == status
                            ? Theme.of(context).primaryColor
                            : Colors.grey.shade300,
                        foregroundColor: event.status == status
                            ? Colors.white
                            : Colors.black,
                      ),
                      child: Text(status),
                    ))
                        .toList(),
                  ),
                ]
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  List<TaskEvent> _getEventsForDay(DateTime day) {
    final utcDay = DateTime.utc(day.year, day.month, day.day);
    return _events[utcDay] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
      _selectedEvents.value = _getEventsForDay(selectedDay);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ## MODIFIED ##: Reverted to light theme with specific blue elements
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAllEvents,
            tooltip: 'Refresh Events',
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(child: Text(_errorMessage!))
          : Column(
        children: [
          TableCalendar<TaskEvent>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            eventLoader: _getEventsForDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: _onDaySelected,
            onFormatChanged: (format) {
              if (_calendarFormat != format) {
                setState(() {
                  _calendarFormat = format;
                });
              }
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarStyle: CalendarStyle(
              // Today's date circle style
              todayDecoration: BoxDecoration(
                color: Colors.blue.shade100,
                shape: BoxShape.circle,
              ),
              // ## MODIFIED ##: Selected date circle is blue
              selectedDecoration: BoxDecoration(
                color: const Color(0xFF2573A6),
                shape: BoxShape.circle,
              ),
              // ## MODIFIED ##: Text inside selected circle is white
              selectedTextStyle: const TextStyle(color: Colors.white),
              // Event marker style
              markerDecoration: BoxDecoration(
                color: Colors.orange.shade400,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: ValueListenableBuilder<List<TaskEvent>>(
              valueListenable: _selectedEvents,
              builder: (context, value, _) {
                if (value.isEmpty) {
                  return const Center(
                      child: Text('No events for this day.'));
                }
                return ListView.builder(
                  itemCount: value.length,
                  itemBuilder: (context, index) {
                    final event = value[index];
                    return Card(
                      // ## MODIFIED ##: Task card background is blue
                      color: const Color(0xFF2573A6),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12.0, vertical: 4.0),
                      child: ListTile(
                        onTap: () => _showTaskDetailsDialog(event),
                        // ## MODIFIED ##: Icons and text are white for contrast
                        leading: Icon(
                          event.isGoogleEvent
                              ? Icons.calendar_month
                              : Icons.check_circle_outline,
                          color: Colors.white,
                        ),
                        title: Text(
                          event.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        trailing: !event.isGoogleEvent
                            ? IconButton(
                          icon: Icon(Icons.delete,
                              color: Colors.white.withOpacity(0.7)),
                          onPressed: () async {
                            await _deleteTask(event.id);
                          },
                        )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}