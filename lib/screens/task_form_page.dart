import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speechtotext/screens/auth_service.dart';

class TaskFormPage extends StatefulWidget {
  final DateTime? selectedDate;

  const TaskFormPage({Key? key, this.selectedDate}) : super(key: key);

  @override
  _TaskFormPageState createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage> with TickerProviderStateMixin {
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
  bool _reminderEnabled = false;

  final List<String> _priorities = ['Low', 'Medium', 'High'];
  final List<String> _categories = ['Work', 'Personal', 'Study', 'Health'];

  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  @override
  void initState() {
    super.initState();
    _detectEmulator();
    _initSpeech();
    _initAnimations();
    if (widget.selectedDate != null) {
      _selectedStartDate = widget.selectedDate;
      _startDateController.text = DateFormat('dd/MM/yyyy').format(widget.selectedDate!);
      _selectedEndDate = widget.selectedDate!.add(const Duration(days: 1));
      _endDateController.text = DateFormat('dd/MM/yyyy').format(_selectedEndDate!);
    }
  }

  Future<void> _selectDate(
      BuildContext context,
      TextEditingController controller,
      Function(DateTime) onDateSelected,
      ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      controller.text = DateFormat('dd/MM/yyyy').format(picked);
      onDateSelected(picked);
    }
  }

  void _saveTask() async {
    if (_isSaving) return;

    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to save a task.'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task title.'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_selectedStartDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a start date.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

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

      await _firestore.collection('Users_Tasks').add(taskData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task saved successfully!'), backgroundColor: Colors.green),
      );

      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error saving task: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save task: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 1,
        shadowColor: Colors.grey.withOpacity(0.2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Create New Task', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField(hint: 'Task Title', controller: _titleController, icon: Icons.title),
            _buildTextField(hint: 'Description (tap mic to speak)', controller: _descriptionController, icon: Icons.description, maxLines: 4, suffixIcon: _buildSpeechButton()),
            _buildSpeechVisualization(),
            _buildStatusWidget(),
            Row(
              children: [
                Expanded(child: _buildTextField(hint: 'Start Date', controller: _startDateController, icon: Icons.calendar_today, readOnly: true, onTap: () => _selectDate(context, _startDateController, (date) => _selectedStartDate = date))),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField(hint: 'End Date', controller: _endDateController, icon: Icons.calendar_today, readOnly: true, onTap: () => _selectDate(context, _endDateController, (date) => _selectedEndDate = date))),
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
            Container(
              margin: const EdgeInsets.only(bottom: 24, top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.notifications_active, color: Colors.blue[700]),
                  const SizedBox(width: 12),
                  const Text('Enable Reminder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Switch(value: _reminderEnabled, onChanged: (value) => setState(() => _reminderEnabled = value), activeTrackColor: Colors.blue.shade200, activeColor: Colors.blue.shade600),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveTask,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 5, shadowColor: Colors.blue.withOpacity(0.4)),
                child: _isSaving
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.save_alt_rounded, size: 20), SizedBox(width: 8), Text('Save Task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey[600])),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSpeechStatus(String status) {
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
        _baseTextForSpeech = '';
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
          setState(() => _recordingDuration = DateTime.now().difference(_recordingStartTime!).inSeconds);
          _updateRecordingDuration();
        }
      });
    }
  }

  String _formatDuration(int seconds) {
    int hours = seconds ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    int remainingSeconds = seconds % 60;
    return hours > 0 ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}' : '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _onSpeechError(dynamic error) {
    print('Speech error occurred: ${error.errorMsg}');
    String errorMsg = error.errorMsg ?? 'Unknown error';
    String displayMessage = errorMsg.contains('timeout') || errorMsg.contains('error_speech_timeout')
        ? 'Speech timeout. On emulators, ensure the virtual mic is enabled in settings.'
        : errorMsg.contains('network') || errorMsg.contains('connection')
        ? 'Network error. Check your internet connection.'
        : errorMsg.contains('permission') || errorMsg.contains('denied')
        ? 'Microphone permission denied. Please enable it in your device settings.'
        : errorMsg.contains('recognizer_busy')
        ? 'Speech recognizer is busy. Please try again.'
        : errorMsg.contains('no_match')
        ? 'No speech detected. Please speak louder or closer to the microphone.'
        : errorMsg.contains('error_audio')
        ? 'Audio error. Make sure the microphone is working.'
        : 'An error occurred: $errorMsg';
    setState(() {
      _isListening = false;
      _waveAnimationController.stop();
      _baseTextForSpeech = '';
      _currentWords = '';
      _statusMessage = displayMessage;
      _recordingStartTime = null;
      _recordingDuration = 0;
    });
  }

  void _startListening() async {
    if (!_speechEnabled || _isListening) return;
    setState(() => _statusMessage = '');
    _baseTextForSpeech = _descriptionController.text;
    if (_baseTextForSpeech.isNotEmpty) _baseTextForSpeech += ' ';
    try {
      await _speechToText.listen(onResult: _onSpeechResult, listenFor: const Duration(minutes: 5), pauseFor: const Duration(seconds: 4), localeId: 'en_US', partialResults: true, onSoundLevelChange: (level) => setState(() => _soundLevel = level));
      setState(() => _isListening = true);
    } catch (e) {
      print('Error starting listening: $e');
      setState(() => _statusMessage = 'Could not start listening: $e');
    }
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() {});
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      final spokenWords = result.recognizedWords;
      _descriptionController.text = _baseTextForSpeech + spokenWords;
      _descriptionController.selection = TextSelection.fromPosition(TextPosition(offset: _descriptionController.text.length));
      _currentWords = spokenWords;
      if (result.finalResult) _baseTextForSpeech = _descriptionController.text + ' ';
    });
  }

  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) controller.text = picked.format(context);
  }

  Widget _buildStatusWidget() {
    if (!(_isEmulator && !_isListening) && _statusMessage.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: (_isEmulator && !_isListening) ? Colors.orange.shade50 : _statusMessage.isNotEmpty ? Colors.red.shade50 : Colors.transparent, borderRadius: BorderRadius.circular(12), border: Border.all(color: (_isEmulator && !_isListening) ? Colors.orange.shade300 : _statusMessage.isNotEmpty ? Colors.red.shade300 : Colors.transparent)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (_isEmulator && !_isListening) ...[
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Emulator detected. Mic may not work as expected.', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500))),
        ],
        if (_statusMessage.isNotEmpty) ...[
          Icon(Icons.error_outline, color: Colors.red.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_statusMessage, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500))),
        ],
      ]),
    );
  }

  Widget _buildTextField({required String hint, required TextEditingController controller, required IconData icon, bool readOnly = false, VoidCallback? onTap, Widget? suffixIcon, int maxLines = 1}) {
    return Container(margin: const EdgeInsets.only(bottom: 16), child: TextFormField(controller: controller, readOnly: readOnly, onTap: onTap, maxLines: maxLines, decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, color: Colors.grey[600]), suffixIcon: suffixIcon, filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blue, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16))));
  }

  Widget _buildDropdownField({required String hint, required String value, required List<String> items, required IconData icon, required ValueChanged<String?> onChanged}) {
    return Container(margin: const EdgeInsets.only(bottom: 16), child: DropdownButtonFormField<String>(value: value, decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, color: Colors.grey[600]), filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blue, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)), items: items.map((String item) => DropdownMenuItem<String>(value: item, child: Text(item))).toList(), onChanged: onChanged));
  }

  Widget _buildSpeechButton() {
    return Padding(padding: const EdgeInsets.only(right: 8.0), child: GestureDetector(onTap: _speechEnabled ? (_isListening ? _stopListening : _startListening) : null, child: AnimatedContainer(duration: const Duration(milliseconds: 300), width: 44, height: 44, decoration: BoxDecoration(color: _isListening ? Colors.red : Colors.blue, shape: BoxShape.circle, boxShadow: [BoxShadow(color: (_isListening ? Colors.red : Colors.blue).withOpacity(0.3), spreadRadius: _isListening ? 4 : 2, blurRadius: 8)]), child: Icon(_isListening ? Icons.stop : Icons.mic, size: 24, color: Colors.white))));
  }

  Widget _buildSpeechVisualization() {
    if (!_isListening) return const SizedBox.shrink();
    return Container(margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: [AnimatedBuilder(animation: _pulseAnimationController, builder: (context, child) => Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.red.withOpacity(_pulseAnimation.value - 0.8), spreadRadius: _pulseAnimation.value * 4, blurRadius: 8)]))), const SizedBox(width: 8), Text('Listening... ${_formatDuration(_recordingDuration)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.red))]), if (_currentWords.isNotEmpty) ...[const SizedBox(height: 8), Text(_currentWords, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black87))], const SizedBox(height: 8), Container(height: 40, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)), child: AnimatedBuilder(animation: _waveAnimationController, builder: (context, child) => CustomPaint(painter: WaveformPainter(animationValue: _waveAnimationController.value, soundLevel: _soundLevel), size: const Size(double.infinity, 40))))]));
  }

  void _initAnimations() {
    _waveAnimationController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _pulseAnimationController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(CurvedAnimation(parent: _pulseAnimationController, curve: Curves.easeInOut));
    _pulseAnimationController.repeat(reverse: true);
  }

  void _detectEmulator() {
    if (Platform.isAndroid) _isEmulator = (Platform.environment['ANDROID_EMULATOR_HARDWARE'] != null) || (Platform.environment['ANDROID_HARDWARE'] != null && (Platform.environment['ANDROID_HARDWARE']!.contains('ranchu') || Platform.environment['ANDROID_HARDWARE']!.contains('goldfish')));
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(onStatus: _onSpeechStatus, onError: _onSpeechError);
      if (!_speechEnabled) _statusMessage = 'Speech recognition not available. Please check microphone permissions.';
      setState(() {});
    } catch (e) {
      print('Error during speech initialization: $e');
      setState(() {
        _speechEnabled = false;
        _statusMessage = 'Error initializing speech: $e';
      });
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
}

class WaveformPainter extends CustomPainter {
  final double animationValue;
  final double soundLevel;

  WaveformPainter({required this.animationValue, required this.soundLevel});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.blue.shade400..strokeWidth = 2..style = PaintingStyle.fill;
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
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, centerY - height / 2, barWidth, height), const Radius.circular(2)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}