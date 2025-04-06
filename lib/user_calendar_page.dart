import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';

class UserCalendarPage extends StatefulWidget {
  const UserCalendarPage({super.key});

  @override
  State<UserCalendarPage> createState() => _UserCalendarPageState();
}

class _UserCalendarPageState extends State<UserCalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('schedules').doc(user.uid).get();
    if (doc.exists) {
      final schedule = doc.data()!['schedule'] as List<dynamic>;
      setState(() {
        _events.clear();
        for (var event in schedule) {
          final startDate = DateTime.parse(event['Start Date']);
          final eventDate = DateTime(startDate.year, startDate.month, startDate.day);
          final eventDetails = {
            'subject': event['Subject'],
            'startTime': event['Start Time'],
            'endTime': event['End Time'],
          };
          if (_events[eventDate] == null) {
            _events[eventDate] = [];
          }
          _events[eventDate]!.add(eventDetails);
        }
      });
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Calendar')),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            eventLoader: _getEventsForDay,
          ),
          const SizedBox(height: 8.0),
          Expanded(
            child: ListView(
              children: _getEventsForDay(_selectedDay!).map((event) => ListTile(
                title: Text(event['subject']),
                subtitle: Text('${event['startTime']} - ${event['endTime']}'),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }
}