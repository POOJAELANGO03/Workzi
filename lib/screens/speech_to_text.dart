import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speechtotext/screens/auth_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'history.dart';

class TaskFormPage extends StatefulWidget {
  final Task? task; // Accept an optional task for editing

  const TaskFormPage({Key? key, this.task}) : super(key: key);

  @override
  _TaskFormPageState createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage>
    with TickerProviderStateMixin {
  bool _isSaving = false;
  String? _taskId; // To store the ID of the task being edited

  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  double _soundLevel = 0.0;
  String _currentWords = '';

  bool _isEmulator = false;
  String _statusMessage = '';

  int _recordingDuration = 0;
  DateTime? _recordingStartTime;

  late AnimationController _waveAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _pulseAnimation;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  final TextEditingController _startTimeController = TextEditingController();
  final TextEditingController _endTimeController = TextEditingController();

  String _selectedPriority = 'Low';
  String _selectedCategory = 'Work';
  bool _reminderEnabled = false;

  final List<String> _priorities = ['Low', 'Medium', 'High'];
  final List<String> _categories = ['Work', 'Personal', 'Study', 'Health'];

  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late FlutterLocalNotificationsPlugin _notificationsPlugin;

  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  @override
  void initState() {
    super.initState();
    _detectEmulator();
    _initSpeech();
    _initAnimations();
    _initNotifications();

    if (widget.task != null) {
      final task = widget.task!;
      _taskId = task.id;
      _titleController.text = task.title;
      _descriptionController.text = task.description;
      _selectedPriority = task.priority;
      _selectedCategory = task.category;
      _startTimeController.text = task.startTime;
      _endTimeController.text = task.endTime;

      if (task.startDate != null) {
        _selectedStartDate = task.startDate;
        _startDateController.text =
            DateFormat('dd/MM/yyyy').format(task.startDate!);
      }
      if (task.endDate != null) {
        _selectedEndDate = task.endDate;
        _endDateController.text =
            DateFormat('dd/MM/yyyy').format(task.endDate!);
      }
    }
  }

  @override
  void dispose() {
    _speechToText.stop();
    _waveAnimationController.dispose();
    _pulseAnimationController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  void _initNotifications() async {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();
    tz.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true);
    const initSettings =
    InitializationSettings(android: androidInit, iOS: iosInit);
    await _notificationsPlugin.initialize(initSettings);

    if (Platform.isAndroid) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> _showTaskSavedNotification(String title) async {
    const androidDetails = AndroidNotificationDetails(
        'task_channel', 'Task Reminders',
        channelDescription: 'Notifications for task reminders',
        importance: Importance.high,
        priority: Priority.high);
    const iosDetails = DarwinNotificationDetails();
    const notificationDetails =
    NotificationDetails(android: androidDetails, iOS: iosDetails);

    final message = _taskId == null
        ? 'Task "$title" has been created.'
        : 'Task "$title" has been updated.';

    await _notificationsPlugin.show(
        title.hashCode, 'Task Set Successfully', message, notificationDetails);
  }

  Future<void> _selectDate(BuildContext context,
      TextEditingController controller, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
      (isStartDate ? _selectedStartDate : _selectedEndDate) ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      controller.text = DateFormat('dd/MM/yyyy').format(picked);
      setState(() {
        if (isStartDate) {
          _selectedStartDate = picked;
        } else {
          _selectedEndDate = picked;
        }
      });
    }
  }

  void _saveTask() async {
    if (_isSaving) return;

    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You must be logged in to save a task.'),
          backgroundColor: Colors.red));
      return;
    }

    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter a task title.'),
          backgroundColor: Colors.red));
      return;
    }

    if (_selectedStartDate != null &&
        _selectedEndDate != null &&
        _selectedEndDate!.isBefore(_selectedStartDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('End date must be after start date.'),
          backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final taskData = {
        'uid': user.uid,
        'title': _titleController.text,
        'description': _descriptionController.text,
        'startDate': _selectedStartDate,
        'endDate': _selectedEndDate,
        'startTime': _startTimeController.text,
        'endTime': _endTimeController.text,
        'priority': _selectedPriority,
        'category': _selectedCategory,
        'reminder': _reminderEnabled,
        'createdAt': _taskId == null
            ? FieldValue.serverTimestamp()
            : widget.task!.createdAt,
        'status': _taskId == null ? 'To Do' : widget.task!.status,
      };

      if (_taskId == null) {
        await _firestore.collection('Users_Tasks').add(taskData);
      } else {
        await _firestore.collection('Users_Tasks').doc(_taskId).update(taskData);
      }

      await _showTaskSavedNotification(_titleController.text);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Task saved successfully!'),
          backgroundColor: Colors.green));

      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      String errorMsg = e.toString().contains('permission-denied')
          ? 'Permission denied. Check Firestore rules.'
          : 'Failed to save task. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _parseAndFillFields(String recognizedText) {
    setState(() {
      final text = recognizedText.toLowerCase();
      final keywords = ['title', 'description', 'start time', 'end time', 'priority', 'category'];
      Map<String, int> keywordIndices = {};

      for (var keyword in keywords) {
        int index = text.indexOf(keyword);
        if (index != -1) {
          keywordIndices[keyword] = index;
        }
      }

      if (keywordIndices.isEmpty) {
        if (_titleController.text.isEmpty) {
          _titleController.text = recognizedText;
        } else {
          _descriptionController.text = (_descriptionController.text.isEmpty ? '' : _descriptionController.text + ' ') + recognizedText;
        }
        return;
      }

      var sortedKeywords = keywordIndices.keys.toList()
        ..sort((a, b) => keywordIndices[a]!.compareTo(keywordIndices[b]!));

      for (int i = 0; i < sortedKeywords.length; i++) {
        final keyword = sortedKeywords[i];
        final startIndex = keywordIndices[keyword]! + keyword.length;
        final endIndex = (i + 1 < sortedKeywords.length)
            ? keywordIndices[sortedKeywords[i + 1]]!
            : text.length;
        var value = text.substring(startIndex, endIndex).trim();

        if (value.startsWith(':') || value.startsWith('-')) {
          value = value.substring(1).trim();
        }

        if (value.isEmpty) continue;

        String finalValue = value;
        if (keyword != 'priority' && keyword != 'category') {
          finalValue = value[0].toUpperCase() + value.substring(1);
        }

        switch (keyword) {
          case 'title':
            _titleController.text = finalValue;
            break;
          case 'description':
            _descriptionController.text = finalValue;
            break;
          case 'start time':
            final time = _parseTime(value);
            if (time != null) _startTimeController.text = time;
            break;
          case 'end time':
            final time = _parseTime(value);
            if (time != null) _endTimeController.text = time;
            break;
          case 'priority':
            final priorityValue = value.toLowerCase();
            if (_priorities.map((p) => p.toLowerCase()).contains(priorityValue)) {
              _selectedPriority = _priorities.firstWhere((p) => p.toLowerCase() == priorityValue);
            }
            break;
          case 'category':
            final categoryValue = value.toLowerCase();
            if (_categories.map((c) => c.toLowerCase()).contains(categoryValue)) {
              _selectedCategory = _categories.firstWhere((c) => c.toLowerCase() == categoryValue);
            }
            break;
        }
      }
    });
  }

  String? _parseTime(String timeString) {
    timeString = timeString.toLowerCase().replaceAll('.', '').trim();
    timeString = timeString.replaceAllMapped(RegExp(r'(\d)(am|pm)'), (m) => '${m[1]} ${m[2]}');
    timeString = timeString.replaceAll(':pm', ' pm').replaceAll(':am', ' am');

    TimeOfDay? timeOfDay;
    final now = DateTime.now();

    try {
      final dateTime = DateFormat.jm().parse(timeString.toUpperCase());
      timeOfDay = TimeOfDay.fromDateTime(dateTime);
    } catch (e) {
      try {
        final parts = timeString.split(':');
        if (parts.length >= 2) {
          final hour = int.tryParse(parts[0].replaceAll(RegExp(r'[^0-9]'), ''));
          final minute = int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
          if (hour != null && minute != null) {
            timeOfDay = TimeOfDay(hour: hour, minute: minute);
          }
        } else {
          final hour = int.tryParse(timeString.replaceAll(RegExp(r'[^0-9]'), ''));
          if (hour != null) {
            int finalHour = hour;
            if (timeString.contains('pm') && hour < 12) finalHour += 12;
            if (timeString.contains('am') && hour == 12) finalHour = 0;
            timeOfDay = TimeOfDay(hour: finalHour, minute: 0);
          }
        }
      } catch (e2) {
        return null;
      }
    }

    if (timeOfDay != null) {
      final dt = DateTime(now.year, now.month, now.day, timeOfDay.hour, timeOfDay.minute);
      return DateFormat('h:mm a').format(dt);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF2573A6);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.task == null ? 'Create New Task' : 'Edit Task',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField(hint: 'Task Title', controller: _titleController, icon: Icons.title),
            _buildTextField(hint: 'Description', controller: _descriptionController, icon: Icons.description, maxLines: 4),
            const SizedBox(height: 16),
            _buildVoiceCommandSection(),
            _buildStatusWidget(),
            Row(
              children: [
                Expanded(child: _buildTextField(hint: 'Start Date', controller: _startDateController, icon: Icons.calendar_today, readOnly: true, onTap: () => _selectDate(context, _startDateController, true))),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField(hint: 'End Date', controller: _endDateController, icon: Icons.calendar_today, readOnly: true, onTap: () => _selectDate(context, _endDateController, false))),
              ],
            ),
            Row(
              children: [
                Expanded(child: _buildTextField(hint: 'Start Time', controller: _startTimeController, icon: Icons.access_time_filled, readOnly: true, onTap: () => _selectTime(context, _startTimeController))),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField(hint: 'End Time', controller: _endTimeController, icon: Icons.access_time, readOnly: true, onTap: () => _selectTime(context, _endTimeController))),
              ],
            ),
            Row(
              children: [
                Expanded(child: _buildDropdownField(hint: 'Priority', value: _selectedPriority, items: _priorities, icon: Icons.flag, onChanged: (value) => setState(() => _selectedPriority = value!))),
                const SizedBox(width: 16),
                Expanded(child: _buildDropdownField(hint: 'Category', value: _selectedCategory, items: _categories, icon: Icons.category, onChanged: (value) => setState(() => _selectedCategory = value!))),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveTask,
                style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 5,
                    shadowColor: themeColor.withOpacity(0.4)),
                child: _isSaving
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_taskId == null ? Icons.save_alt_rounded : Icons.edit_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(_taskId == null ? 'Save Task' : 'Update Task', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceCommandSection() {
    const themeColor = Color(0xFF2573A6);
    return Column(
      children: [
        Center(
          child: GestureDetector(
            onTap: _speechEnabled ? (_isListening ? _stopListening : _startListening) : null,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _isListening ? Colors.red.shade700 : themeColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_isListening ? Colors.red : themeColor).withOpacity(0.4),
                        spreadRadius: _isListening ? _pulseAnimation.value * 2 : 4,
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _isListening ? "I'm listening..." : "Tap mic to fill form with voice",
          style: TextStyle(
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        _buildSpeechVisualization(),
      ],
    );
  }

  void _onSpeechStatus(String status) {
    setState(() {
      if (status == 'listening') {
        _isListening = true;
        _waveAnimationController.repeat();
        _pulseAnimationController.repeat(reverse: true);
        _recordingStartTime = DateTime.now();
        _updateRecordingDuration();
      } else if (status == 'notListening' || status == 'done') {
        _isListening = false;
        _soundLevel = 0.0;
        _waveAnimationController.stop();
        _pulseAnimationController.stop();
        _currentWords = '';
        _recordingStartTime = null;
        _recordingDuration = 0;
      }
    });
  }

  void _updateRecordingDuration() {
    if (_recordingStartTime != null && _isListening) {
      Future.delayed(const Duration(seconds: 1), () {
        if (_isListening && _recordingStartTime != null) {
          setState(() {
            _recordingDuration = DateTime.now().difference(_recordingStartTime!).inSeconds;
          });
          _updateRecordingDuration();
        }
      });
    }
  }

  String _formatDuration(int seconds) {
    int hours = seconds ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    int remainingSeconds = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  void _onSpeechError(dynamic error) {
    print('Speech error occurred: ${error.errorMsg}');
    String errorMsg = error.errorMsg ?? 'Unknown error';
    String displayMessage = '';
    if (errorMsg.contains('timeout') || errorMsg.contains('error_speech_timeout')) {
      displayMessage = 'Speech timeout. On emulators, ensure the virtual mic is enabled in settings.';
    } else if (errorMsg.contains('network') || errorMsg.contains('connection')) {
      displayMessage = 'Network error. Check your internet connection.';
    } else if (errorMsg.contains('permission') || errorMsg.contains('denied')) {
      displayMessage = 'Microphone permission denied. Please enable it in your device settings.';
    } else if (errorMsg.contains('recognizer_busy')) {
      displayMessage = 'Speech recognizer is busy. Please try again.';
    } else if (errorMsg.contains('no_match')) {
      displayMessage = 'No speech detected. Please speak louder or closer to the microphone.';
    } else if (errorMsg.contains('error_audio')) {
      displayMessage = 'Audio error. Make sure the microphone is working.';
    } else {
      displayMessage = 'An error occurred: $errorMsg';
    }
    setState(() {
      _isListening = false;
      _waveAnimationController.stop();
      _pulseAnimationController.stop();
      _currentWords = '';
      _statusMessage = displayMessage;
      _recordingStartTime = null;
      _recordingDuration = 0;
    });
  }

  void _startListening() async {
    if (!_speechEnabled || _isListening) return;
    setState(() {
      _statusMessage = '';
    });
    try {
      await _speechToText.listen(
        onResult: _onSpeechResult,
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 5),
        localeId: 'en_US',
        partialResults: true,
        onSoundLevelChange: (level) {
          setState(() {
            _soundLevel = level;
          });
        },
      );
      setState(() {
        _isListening = true;
      });
    } catch (e) {
      print('Error starting listening: $e');
      setState(() {
        _statusMessage = 'Could not start listening: $e';
      });
    }
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() {});
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _currentWords = result.recognizedWords;
    });

    if (result.finalResult && result.recognizedWords.isNotEmpty) {
      _parseAndFillFields(result.recognizedWords);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _currentWords = '';
          });
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      controller.text = picked.format(context);
    }
  }

  Widget _buildStatusWidget() {
    Widget? content;
    Color backgroundColor = Colors.transparent;
    Color borderColor = Colors.transparent;
    if (_isEmulator && !_isListening) {
      backgroundColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade300;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Emulator detected. Mic may not work as expected.', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500)),
          ),
        ],
      );
    }
    if (_statusMessage.isNotEmpty) {
      backgroundColor = Colors.red.shade50;
      borderColor = Colors.red.shade300;
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_statusMessage, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500))),
        ],
      );
    }
    if (content == null) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
      child: content,
    );
  }

  Widget _buildTextField({
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
    int maxLines = 1,
  }) {
    const themeColor = Color(0xFF2573A6);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.grey[600]),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: themeColor, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String hint,
    required String value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    const themeColor = Color(0xFF2573A6);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.grey[600]),
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: themeColor, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        items: items.map((String item) {
          return DropdownMenuItem<String>(value: item, child: Text(item));
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSpeechVisualization() {
    if (!_isListening) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.5), spreadRadius: _pulseAnimation.value * 2, blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 8),
              Text('Listening... ${_formatDuration(_recordingDuration)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.red)),
            ],
          ),
          if (_currentWords.isNotEmpty) ...[
            const SizedBox(height: 8),
            // ## RECTIFIED TYPO ##
            Text('"$_currentWords"', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: Colors.black87)),
          ],
          const SizedBox(height: 8),
          Container(
            height: 40,
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
            child: AnimatedBuilder(
              animation: _waveAnimationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: WaveformPainter(animationValue: _waveAnimationController.value, soundLevel: _soundLevel),
                  size: const Size(double.infinity, 40),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _initAnimations() {
    _waveAnimationController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _pulseAnimationController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(CurvedAnimation(parent: _pulseAnimationController, curve: Curves.easeInOut));
  }

  void _detectEmulator() {
    if (Platform.isAndroid) {
      _isEmulator = (Platform.environment['ANDROID_EMULATOR_HARDWARE'] != null) || (Platform.environment['ANDROID_HARDWARE'] != null && (Platform.environment['ANDROID_HARDWARE']!.contains('ranchu') || Platform.environment['ANDROID_HARDWARE']!.contains('goldfish')));
    }
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(onStatus: _onSpeechStatus, onError: _onSpeechError);
      if (!_speechEnabled) {
        _statusMessage = 'Speech recognition not available. Please check microphone permissions.';
      }
      setState(() {});
    } catch (e) {
      print('Error during speech initialization: $e');
      setState(() {
        _speechEnabled = false;
        _statusMessage = 'Error initializing speech: $e';
      });
    }
  }
}

class WaveformPainter extends CustomPainter {
  final double animationValue;
  final double soundLevel;

  WaveformPainter({required this.animationValue, required this.soundLevel});

  @override
  void paint(Canvas canvas, Size size) {
    const themeColor = Color(0xFF2573A6);
    final paint = Paint()
      ..color = themeColor
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;

    final centerY = size.height / 2;
    final barWidth = 2.5;
    final barSpacing = 2.0;
    final numberOfBars = (size.width / (barWidth + barSpacing)).floor();

    for (int i = 0; i < numberOfBars; i++) {
      final x = i * (barWidth + barSpacing);
      final soundMultiplier = 1.0 + (soundLevel * 1.5);
      final animationOffset = (animationValue + i * 0.05) % 1.0;
      final waveHeight = (math.sin(animationOffset * 2 * math.pi) * (size.height * 0.3) * soundMultiplier) + (math.sin((animationOffset * 1.5) * 2 * math.pi) * (size.height * 0.1) * soundMultiplier);
      final height = (2.0 + waveHeight.abs()).clamp(2.0, size.height);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centerY - height / 2, barWidth, height),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
          oldDelegate.soundLevel != soundLevel;
}