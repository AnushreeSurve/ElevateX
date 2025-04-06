import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'app_theme.dart';
import 'package:flutter/foundation.dart' show kDebugMode; // Ensure correct import for kDebugMode

final functions = FirebaseFunctions.instanceFor(region: 'asia-south2');

class ResumePage extends StatefulWidget {
  const ResumePage({Key? key}) : super(key: key);

  @override
  State<ResumePage> createState() => _ResumePageState();
}

class _ResumePageState extends State<ResumePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _jobTitleController = TextEditingController();
  final TextEditingController _experienceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _skillsController = TextEditingController();
  final TextEditingController _educationController = TextEditingController();
  bool _hasCertifications = false;
  final TextEditingController _certificationDetailsController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  late String uid;
  bool _isUserReady = false;
  bool _isLoading = false;
  int currentStep = 0;
  bool hasUploaded = false;

  @override
  void initState() {
    super.initState();
    _initializeUser().then((_) {
      _loadResumeData();
      setState(() {
        _isUserReady = true;
        currentStep = 0;
      });
    });
  }

  Future<void> _initializeUser() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      UserCredential credential = await FirebaseAuth.instance.signInAnonymously();
      user = credential.user;
    }
    uid = user!.uid;
  }

  Future<void> _loadResumeData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snapshot = await FirebaseFirestore.instance.collection('resume').doc(user.uid).get();
      if (snapshot.exists) {
        final data = snapshot.data()!;
        setState(() {
          _jobTitleController.text = data['current_job_title'] ?? '';
          _experienceController.text = data['years_of_experience'] ?? '';
          _descriptionController.text = data['brief_description'] ?? '';
          _skillsController.text = (data['key_skills_tools'] as List<dynamic>?)?.join(', ') ?? '';
          _educationController.text = data['highest_education'] ?? '';
          _certificationDetailsController.text = (data['certifications'] as List<dynamic>?)?.join(', ') ?? '';
          _hasCertifications = _certificationDetailsController.text.isNotEmpty;
        });
      }
    }
  }

  Future<void> _saveResumeData() async {
    setState(() => _isLoading = true);
    try {
      if (_formKey.currentState!.validate()) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final skills = _skillsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          final certs = _hasCertifications
              ? _certificationDetailsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
              : [];
          await FirebaseFirestore.instance.collection('resume').doc(user.uid).set({
            'current_job_title': _jobTitleController.text.trim(),
            'years_of_experience': _experienceController.text.trim(),
            'brief_description': _descriptionController.text.trim(),
            'key_skills_tools': skills.isEmpty ? ['Not Found'] : skills,
            'highest_education': _educationController.text.trim(),
            'certifications': certs.isEmpty ? ['Not Found'] : certs,
            'hasCertifications': _hasCertifications,
          }, SetOptions(merge: true));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Snapshot saved successfully!')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadResumePdf() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      if (result == null || result.files.single.path == null) {
        throw Exception('No file selected');
      }

      final file = File(result.files.single.path!);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      if (kDebugMode) print('Uploading resume for UID: ${user.uid}');
      final ref = FirebaseStorage.instance.ref().child('resumes/${user.uid}/resume.pdf');
      await ref.putFile(file);
      if (kDebugMode) print('Resume uploaded to Firebase Storage');

      // Call the upload_resume Cloud Function for server-side confirmation
      final callable = functions.httpsCallable('upload_resume');
      final response = await callable.call({
        'uid': user.uid,
        'filename': 'resume.pdf',
      });

      if (response.data['status'] == 'success') {
        if (kDebugMode) print('Server confirmed upload');
        setState(() {
          currentStep = 1;
          hasUploaded = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.data['message'])),
        );
      } else {
        throw Exception(response.data['error'] ?? 'Server failed to confirm upload');
      }
    } catch (e) {
      if (kDebugMode) print('Upload failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _parseResumeByVision() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final callable = functions.httpsCallable('parse_resume_by_vision');
      await callable.call({'uid': user.uid});
      setState(() => currentStep = 2);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resume parsed successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Parsing failed: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _extractResumeFields() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final callable = functions.httpsCallable('extract_resume_fields');
      await callable.call({'uid': user.uid});
      await _loadResumeData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fields extracted with spaCy')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Extraction (spaCy) failed: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _extractResumeFieldsOpenAI() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final callable = functions.httpsCallable('extract_resume_openai');
      await callable.call({'uid': user.uid});
      await _loadResumeData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fields extracted with OpenAI')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Extraction (OpenAI) failed: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  ButtonStyle _disabledButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: color5,
      foregroundColor: color4,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isUserReady) {
      return Scaffold(
        appBar: AppBar(title: const Text("Your Professional Snapshot")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Your Professional Snapshot')),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - AppBar().preferredSize.height - MediaQuery.of(context).padding.top,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _jobTitleController,
                            decoration: const InputDecoration(labelText: 'Current job title or role'),
                          ),
                          TextFormField(
                            controller: _experienceController,
                            decoration: const InputDecoration(labelText: 'Years of work experience'),
                            keyboardType: TextInputType.number,
                          ),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(labelText: 'Brief description of work/projects'),
                            maxLines: 3,
                          ),
                          TextFormField(
                            controller: _skillsController,
                            decoration: const InputDecoration(labelText: 'Key skills or tools'),
                          ),
                          TextFormField(
                            controller: _educationController,
                            decoration: const InputDecoration(labelText: 'Highest education level & field'),
                          ),
                          SwitchListTile(
                            title: Text(
                              'Do you have relevant certifications?',
                              style: const TextStyle(color: color1),
                            ),
                            value: _hasCertifications,
                            onChanged: (value) {
                              setState(() => _hasCertifications = value);
                            },
                          ),
                          if (_hasCertifications)
                            TextFormField(
                              controller: _certificationDetailsController,
                              decoration: const InputDecoration(labelText: 'Certification details'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: _uploadResumePdf,
                          child: const Text('1️⃣ Upload Resume'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: currentStep >= 1 ? _parseResumeByVision : null,
                          style: currentStep < 1 ? _disabledButtonStyle() : null,
                          child: const Text('2️⃣ Parse Resume'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: currentStep >= 2 ? _extractResumeFields : null,
                          style: currentStep < 2 ? _disabledButtonStyle() : null,
                          child: const Text('3️⃣ Extract (spaCy)'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: currentStep >= 2 ? _extractResumeFieldsOpenAI : null,
                          style: currentStep < 2 ? _disabledButtonStyle() : null,
                          child: const Text('4️⃣ Extract (OpenAI)'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: _saveResumeData,
                          child: const Text('5️⃣ Save Snapshot'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _jobTitleController.dispose();
    _experienceController.dispose();
    _descriptionController.dispose();
    _skillsController.dispose();
    _educationController.dispose();
    _certificationDetailsController.dispose();
    super.dispose();
  }
}