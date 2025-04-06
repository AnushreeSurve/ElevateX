import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'user_calendar_page.dart';

class ScheduleCoursesPage extends StatefulWidget {
  const ScheduleCoursesPage({super.key});

  @override
  State<ScheduleCoursesPage> createState() => _ScheduleCoursesPageState();
}

class _ScheduleCoursesPageState extends State<ScheduleCoursesPage> {
  bool _isLoading = false;
  String _errorMessage = '';
  DateTime? _startDate;
  DateTime? _endDate;
  final List<String> _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final Map<String, bool> _selectedDays = {};
  String? _selectedTimeSlot;
  final List<String> _timeSlots = ['9:00-11:00', '13:00-15:00', '15:00-17:00'];
  double _hoursPerDay = 2.0;

  @override
  void initState() {
    super.initState();
    for (var day in _days) {
      _selectedDays[day] = false;
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2026),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  bool _canSchedule() {
    return _startDate != null &&
        _endDate != null &&
        _selectedDays.values.any((selected) => selected) &&
        _selectedTimeSlot != null;
  }

  Future<void> _blockCalendar() async {
    setState(() => _isLoading = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south2')
          .httpsCallable('schedule_and_block_courses');

      final data = {
        "start_date": _startDate!.toIso8601String().split('T')[0],
        "end_date": _endDate!.toIso8601String().split('T')[0],
        "selected_days": _selectedDays.entries
            .where((entry) => entry.value)
            .map((entry) => entry.key)
            .toList(),
        "time_slot": _selectedTimeSlot,
        "hours_per_day": _hoursPerDay,
      };

      final response = await callable.call(data);
      if (response.data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schedule saved successfully!')),
        );
        // Navigate to the UserCalendarPage to view the schedule
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserCalendarPage()),
        );
      } else {
        throw Exception(response.data['error']);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save schedule: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save schedule: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Schedule Courses')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Schedule Courses')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule Courses')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: () => _pickDate(true),
                    child: Text(_startDate == null ? 'Start Date' : _startDate!.toString().split(' ')[0]),
                  ),
                  ElevatedButton(
                    onPressed: () => _pickDate(false),
                    child: Text(_endDate == null ? 'End Date' : _endDate!.toString().split('T')[0]),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Preferred Days:'),
              Wrap(
                spacing: 8.0,
                children: _days.map((day) => FilterChip(
                  label: Text(day),
                  selected: _selectedDays[day]!,
                  onSelected: (selected) {
                    setState(() => _selectedDays[day] = selected);
                  },
                )).toList(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedTimeSlot,
                hint: const Text('Select Time Slot'),
                items: _timeSlots.map((slot) => DropdownMenuItem(
                  value: slot,
                  child: Text(slot),
                )).toList(),
                onChanged: (value) => setState(() => _selectedTimeSlot = value),
              ),
              const SizedBox(height: 16),
              Slider(
                value: _hoursPerDay,
                min: 1.0,
                max: 8.0,
                divisions: 7,
                label: '$_hoursPerDay hours/day',
                onChanged: (value) => setState(() => _hoursPerDay = value),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.schedule),
                label: const Text('Save Schedule'),
                onPressed: _canSchedule() ? _blockCalendar : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}