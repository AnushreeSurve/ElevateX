import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'questions_page.dart';
import 'resume.dart';
import 'jd_page.dart';
import 'user_calendar_page.dart'; // Import the new page
import 'app_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String company = '';
  String position = '';
  String location = '';
  String deadline = '';

  final avatarAlignment = Alignment.center;
  final goalBlockAlignment = Alignment.center;
  final goalButtonAlignment = Alignment.center;
  final resumeButtonAlignment = Alignment.center;
  final jdButtonAlignment = Alignment.center;
  final calendarButtonAlignment = Alignment.center; // Added for calendar button
  final jdButtonPadding = const EdgeInsets.only(top: 24);
  final avatarPadding = const EdgeInsets.only(top: 40, bottom: 24);
  final goalBlockPadding = const EdgeInsets.only(top: 16);
  final goalButtonPadding = const EdgeInsets.only(top: 12);
  final resumeButtonPadding = const EdgeInsets.only(top: 12);
  final calendarButtonPadding = const EdgeInsets.only(top: 12); // Added for calendar button

  @override
  void initState() {
    super.initState();
    loadGoalData();
  }

  Future<void> loadGoalData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('udata').doc(user.uid).get();
    if (doc.exists) {
      final data = doc.data()!;
      setState(() {
        company = data['company'] ?? '';
        position = data['position'] ?? '';
        location = data['location'] ?? '';
        deadline = data['deadline'] ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: avatarPadding,
              child: Align(
                alignment: avatarAlignment,
                child: const CircleAvatar(
                  radius: 60,
                  backgroundColor: color3,
                  child: Icon(
                    Icons.person,
                    size: 100,
                    color: color1,
                  ),
                ),
              ),
            ),
            Padding(
              padding: goalBlockPadding,
              child: Align(
                alignment: goalBlockAlignment,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🎯 My Goal',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Company: $company',
                      style: const TextStyle(
                        fontSize: 16,
                        color: color1,
                      ),
                    ),
                    Text(
                      'Position: $position',
                      style: const TextStyle(
                        fontSize: 16,
                        color: color1,
                      ),
                    ),
                    Text(
                      'Location: $location',
                      style: const TextStyle(
                        fontSize: 16,
                        color: color1,
                      ),
                    ),
                    Text(
                      'Deadline: $deadline',
                      style: const TextStyle(
                        fontSize: 16,
                        color: color1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: goalButtonPadding,
              child: Align(
                alignment: goalButtonAlignment,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Goal'),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const QuestionsPage()));
                  },
                ),
              ),
            ),
            Padding(
              padding: resumeButtonPadding,
              child: Align(
                alignment: resumeButtonAlignment,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.description),
                  label: const Text('Edit Resume'),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ResumePage()));
                  },
                ),
              ),
            ),
            Padding(
              padding: jdButtonPadding,
              child: Align(
                alignment: jdButtonAlignment,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Generate JD'),
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );

                    try {
                      final callable = FirebaseFunctions.instanceFor(region: 'asia-south2')
                          .httpsCallable('generate_jd');
                      final response = await callable.call({'uid': user.uid});

                      Navigator.pop(context);
                      if (response.data['status'] == 'success') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('JD generated successfully!')),
                        );
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const JDPage()));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('JD generation failed: ${response.data['error']}')),
                        );
                      }
                    } catch (e) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  },
                ),
              ),
            ),
            Padding(
              padding: calendarButtonPadding,
              child: Align(
                alignment: calendarButtonAlignment,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('View Calendar'),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const UserCalendarPage()));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}