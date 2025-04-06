import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';

class QuestionsPage extends StatefulWidget {
  const QuestionsPage({super.key});

  @override
  State<QuestionsPage> createState() => _QuestionsPageState();
}

class _QuestionsPageState extends State<QuestionsPage> {
  final companyController = TextEditingController();
  final positionController = TextEditingController();
  final locationController = TextEditingController();
  final deadlineController = TextEditingController();

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  Future<void> _loadExistingData() async {
    final user = FirebaseAuth.instance.currentUser!;
    final doc = await FirebaseFirestore.instance.collection('udata').doc(user.uid).get();

    if (doc.exists && doc.data() != null) {
      final data = doc.data()!;
      companyController.text = data['company'] ?? '';
      positionController.text = data['position'] ?? '';
      locationController.text = data['location'] ?? '';
      deadlineController.text = data['deadline'] ?? '';
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _saveData() async {
    final user = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance.collection('udata').doc(user.uid).set({
      'company': companyController.text,
      'position': positionController.text,
      'location': locationController.text,
      'deadline': deadlineController.text,
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  @override
  void dispose() {
    companyController.dispose();
    positionController.dispose();
    locationController.dispose();
    deadlineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Survey')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: companyController,
              decoration: const InputDecoration(labelText: 'Company'),
            ),
            TextField(
              controller: positionController,
              decoration: const InputDecoration(labelText: 'Position'),
            ),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            TextField(
              controller: deadlineController,
              decoration: const InputDecoration(labelText: 'Deadline'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saveData,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}