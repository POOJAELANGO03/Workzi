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

class TaskFormPage extends StatefulWidget {
  const TaskFormPage({Key? key}) : super(key: key);

  @override
  _TaskFormPageState createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage>
    with TickerProviderStateMixin {
  bool _isSaving = false;

  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  double _soundLevel = 0.0;
  String _currentWords = '';
  String _baseTextForSpeech = '';

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
  bool _reminderEnabled = true;

  final List<String> _priorities = ['Low', 'Medium', 'High'];
  final List<String> _categories = ['Work', 'Personal', 'Study', 'Health'];

  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  @override
  void initState() {
    super.initState();
    _detectEmulator();
    _initSpeech();
    _initAnimations();
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

  Future<void> _showTaskSavedNotification(String title, String taskId) async {
    const androidDetails = AndroidNotificationDetails(
      'task_channel', 'Task Reminders',
      channelDescription: 'Notifications for task reminders',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      (taskId + "created").hashCode,
      'Task Set Successfully',
      'Task "$title" has been created.',
      notificationDetails,
      payload: taskId,
    );
  }

  Future<void> _selectDate(
      BuildContext context,
      TextEditingController controller,
      bool isStartDate,
      ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      controller.text = DateFormat('dd/MM/yyyy').format(picked);
      if (isStartDate) {
        _selectedStartDate = picked;
      } else {
        _selectedEndDate = picked;
      }
    }
  }

  void _saveTask() async {
    if (_isSaving) return;
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must be logged in to save a task.'), backgroundColor: Colors.red));
      return;
    }
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a task title.'), backgroundColor: Colors.red));
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
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'To Do',
      };
      final docRef = await _firestore.collection('Users_Tasks').add(taskData);
      await _showTaskSavedNotification(_titleController.text, docRef.id);

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Task saved successfully!'),
            backgroundColor: const Color(0xFF2573A6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }

      if (Navigator.canPop(context)) Navigator.of(context).pop();
    } catch (e) {
      String errorMsg = e.toString().contains('permission-denied') ? 'Permission denied. Check your Firestore rules.' : 'Failed to save task. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ## MODIFIED ##: Defined theme color for reuse throughout the build method.
    const themeColor = Color(0xFF2573A6);

    return Scaffold(
      appBar: AppBar(
        // ## MODIFIED ##: AppBar styled to match the theme.
        title: const Text('Create New Task'),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField(hint: 'Task Title', controller: _titleController, icon: Icons.title_rounded),
            _buildTextField(
              hint: 'Description (tap mic)',
              controller: _descriptionController,
              icon: Icons.description_rounded,
              maxLines: 4,
              suffixIcon: _buildSpeechButton(),
            ),
            _buildSpeechVisualization(),
            _buildStatusWidget(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildTextField(hint: 'Start Date', controller: _startDateController, icon: Icons.calendar_today_rounded, readOnly: true, onTap: () => _selectDate(context, _startDateController, true))),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField(hint: 'End Date', controller: _endDateController, icon: Icons.calendar_today_rounded, readOnly: true, onTap: () => _selectDate(context, _endDateController, false))),
              ],
            ),
            Row(
              children: [
                Expanded(child: _buildTextField(hint: 'Start Time', controller: _startTimeController, icon: Icons.access_time_filled_rounded, readOnly: true, onTap: () => _selectTime(context, _startTimeController))),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField(hint: 'End Time', controller: _endTimeController, icon: Icons.access_time_rounded, readOnly: true, onTap: () => _selectTime(context, _endTimeController))),
              ],
            ),
            Row(
              children: [
                Expanded(child: _buildDropdownField(hint: 'Priority', value: _selectedPriority, items: _priorities, icon: Icons.flag_rounded, onChanged: (value) => setState(() => _selectedPriority = value!))),
                const SizedBox(width: 16),
                Expanded(child: _buildDropdownField(hint: 'Category', value: _selectedCategory, items: _categories, icon: Icons.category_rounded, onChanged: (value) => setState(() => _selectedCategory = value!))),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_active_rounded, color: themeColor),
              title: const Text('Enable Reminder'),
              trailing: Switch(
                // ## MODIFIED ##: Switch styled to match the theme.
                value: _reminderEnabled,
                onChanged: (value) => setState(() => _reminderEnabled = value),
                activeColor: themeColor,
                activeTrackColor: themeColor.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveTask,
                // ## MODIFIED ##: Button styled to match the theme.
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : const Text('Save Task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper and Speech-to-Text methods ---

  void _onSpeechStatus(String status) {
    if (mounted) {
      setState(() {
        if (status == 'listening') {
          _isListening = true;
          _waveAnimationController.repeat();
          _recordingStartTime = DateTime.now();
          _updateRecordingDuration();
        } else if (status == 'notListening' || status == 'done') {
          _isListening = false;
          _soundLevel = 0.0;
          _waveAnimationController.stop();
          _pulseAnimationController.stop();
          _recordingStartTime = null;
        }
      });
    }
  }

  void _updateRecordingDuration() {
    if (_isListening && _recordingStartTime != null) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && _isListening) {
          setState(() => _recordingDuration = DateTime.now().difference(_recordingStartTime!).inSeconds);
          _updateRecordingDuration();
        }
      });
    }
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }

  void _onSpeechError(dynamic error) {
    if (mounted) setState(() => _statusMessage = 'Error: ${error.errorMsg}');
  }

  void _startListening() async {
    if (!_speechEnabled || _isListening) return;
    _baseTextForSpeech = _descriptionController.text;
    if (_baseTextForSpeech.isNotEmpty) _baseTextForSpeech += ' ';

    setState(() {
      _isListening = true;
    });

    await _speechToText.listen(onResult: _onSpeechResult, listenFor: const Duration(minutes: 1), pauseFor: const Duration(seconds: 2), onSoundLevelChange: (level) => setState(() => _soundLevel = level));
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
    });
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _currentWords = result.recognizedWords;
      _descriptionController.text = _baseTextForSpeech + result.recognizedWords;
    });
  }

  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) controller.text = picked.format(context);
  }

  Widget _buildStatusWidget() {
    if (_statusMessage.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(_statusMessage, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _buildTextField({required String hint, required TextEditingController controller, required IconData icon, bool readOnly = false, VoidCallback? onTap, Widget? suffixIcon, int maxLines = 1}) {
    const themeColor = Color(0xFF2573A6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: hint,
          prefixIcon: Icon(icon, color: Colors.grey.shade600),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: themeColor, width: 2)),
          filled: true,
          fillColor: Colors.grey.shade100,
        ),
      ),
    );
  }

  Widget _buildDropdownField({required String hint, required String value, required List<String> items, required IconData icon, required ValueChanged<String?> onChanged}) {
    const themeColor = Color(0xFF2573A6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: hint,
          prefixIcon: Icon(icon, color: Colors.grey.shade600),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: themeColor, width: 2)),
          filled: true,
          fillColor: Colors.grey.shade100,
        ),
        items: items.map((String item) => DropdownMenuItem<String>(value: item, child: Text(item))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSpeechButton() {
    const themeColor = Color(0xFF2573A6);
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: _speechEnabled ? (_isListening ? _stopListening : _startListening) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            // ## MODIFIED ##: Mic button uses theme color.
            color: _isListening ? Colors.red.shade400 : themeColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (_isListening ? Colors.red.shade400 : themeColor).withOpacity(0.3),
                spreadRadius: _isListening ? 4 : 2,
                blurRadius: 8,
              ),
            ],
          ),
          child: Icon(_isListening ? Icons.stop_rounded : Icons.mic_rounded, size: 24, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSpeechVisualization() {
    const themeColor = Color(0xFF2573A6);
    // The "Listening..." UI now uses the red color for a distinct "recording" state, which is a good UX practice.
    // If you prefer it to be blue, you can change Colors.red to themeColor in the BoxDecoration and TextStyle below.
    if (!_isListening) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseAnimationController,
                builder: (context, child) => Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(_pulseAnimation.value - 0.8),
                        spreadRadius: _pulseAnimation.value * 4,
                        blurRadius: 8,
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Listening... ${_formatDuration(_recordingDuration)}',
                style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.red),
              ),
            ],
          ),
          if (_currentWords.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _currentWords,
              textAlign: TextAlign.center,
              style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black87),
            )
          ],
          const SizedBox(height: 8),
          Container(
            height: 40,
            width: double.infinity,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: AnimatedBuilder(
              animation: _waveAnimationController,
              builder: (context, child) => CustomPaint(
                painter: WaveformPainter(
                  animationValue: _waveAnimationController.value,
                  soundLevel: _soundLevel,
                ),
                size: const Size(double.infinity, 40),
              ),
            ),
          )
        ],
      ),
    );
  }

  void _initAnimations() {
    _waveAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _pulseAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(CurvedAnimation(parent: _pulseAnimationController, curve: Curves.easeInOut));
  }

  void _detectEmulator() {
    if (Platform.isAndroid) _isEmulator = (Platform.environment['ANDROID_EMULATOR_HARDWARE'] != null);
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(onStatus: _onSpeechStatus, onError: _onSpeechError);
      if (!_speechEnabled) _statusMessage = 'Speech recognition not available.';
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Error initializing speech: $e');
    }
  }
}

class WaveformPainter extends CustomPainter {
  final double animationValue;
  final double soundLevel;
  WaveformPainter({required this.animationValue, required this.soundLevel});

  @override
  void paint(Canvas canvas, Size size) {
    // ## MODIFIED ##: Changed the waveform color to red to match the "listening" theme.
    final paint = Paint()..color = Colors.red.shade300..style = PaintingStyle.fill;
    final centerY = size.height / 2;
    const barWidth = 3.0;
    const barSpacing = 2.0;
    final numberOfBars = (size.width / (barWidth + barSpacing)).floor();

    for (int i = 0; i < numberOfBars; i++) {
      final x = i * (barWidth + barSpacing);
      final soundMultiplier = 1.0 + (soundLevel * 15);
      final animationOffset = (animationValue + i * 0.05) % 1.0;
      final waveHeight = (math.sin(animationOffset * 2 * math.pi) * (size.height * 0.4) * soundMultiplier);
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