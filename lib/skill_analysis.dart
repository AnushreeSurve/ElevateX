import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'course_suggestions.dart'; // Import the new page
import 'app_theme.dart'; // Import the theme to access colors

class SkillAnalysisPage extends StatefulWidget {
  const SkillAnalysisPage({super.key});

  @override
  State<SkillAnalysisPage> createState() => _SkillAnalysisPageState();
}

class _SkillAnalysisPageState extends State<SkillAnalysisPage> {
  String educationGap = '';
  List<String> highPriorityGaps = [];
  List<String> lowPriorityGaps = [];
  List<String> missingTechnicalSkills = [];
  List<String> missingSoftSkills = [];

  List<bool> highPriorityChecked = [];
  List<bool> lowPriorityChecked = [];
  List<bool> technicalSkillsChecked = [];
  List<bool> softSkillsChecked = [];

  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    loadAnalysis();
  }

  Future<void> loadAnalysis({bool forceRefresh = false}) async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          errorMessage = 'User not logged in.';
          isLoading = false;
        });
        return;
      }

      final analysisDoc = await FirebaseFirestore.instance
          .collection('skill_analysis')
          .doc(user.uid)
          .get();

      if (analysisDoc.exists && !forceRefresh) {
        final data = analysisDoc.data()!;
        setState(() {
          educationGap = data['education_gap'] ?? 'No education gap';
          highPriorityGaps = List<String>.from(data['high_priority_gaps'] ?? []);
          lowPriorityGaps = List<String>.from(data['low_priority_gaps'] ?? []);
          missingTechnicalSkills = List<String>.from(data['technical_skills'] ?? []);
          missingSoftSkills = List<String>.from(data['soft_skills'] ?? []);
        });
      } else {
        final callable = FirebaseFunctions.instanceFor(region: 'asia-south2')
            .httpsCallable('analyze_missing_skills');
        final response = await callable.call({'uid': user.uid});

        if (response.data['status'] == 'success') {
          final data = response.data['result'];
          setState(() {
            educationGap = data['education_gap'] ?? 'No education gap';
            highPriorityGaps = List<String>.from(data['high_priority_gaps'] ?? []);
            lowPriorityGaps = List<String>.from(data['low_priority_gaps'] ?? []);
            missingTechnicalSkills = List<String>.from(data['technical_skills'] ?? []);
            missingSoftSkills = List<String>.from(data['soft_skills'] ?? []);
          });
        } else {
          throw Exception(response.data['error']);
        }
      }

      setState(() {
        highPriorityChecked = List<bool>.filled(highPriorityGaps.length, false);
        lowPriorityChecked = List<bool>.filled(lowPriorityGaps.length, false);
        technicalSkillsChecked = List<bool>.filled(missingTechnicalSkills.length, false);
        softSkillsChecked = List<bool>.filled(missingSoftSkills.length, false);
      });

      await loadCheckboxStates(user.uid);

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading analysis: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  Future<void> loadCheckboxStates(String uid) async {
    final selectionsDoc = await FirebaseFirestore.instance
        .collection('skill_analysis_selections')
        .doc(uid)
        .get();

    if (selectionsDoc.exists) {
      final data = selectionsDoc.data()!;
      setState(() {
        highPriorityChecked = List<bool>.from(data['high_priority_checked'] ?? highPriorityChecked);
        lowPriorityChecked = List<bool>.from(data['low_priority_checked'] ?? lowPriorityChecked);
        technicalSkillsChecked = List<bool>.from(data['technical_skills_checked'] ?? technicalSkillsChecked);
        softSkillsChecked = List<bool>.from(data['soft_skills_checked'] ?? softSkillsChecked);
      });
    }
  }

  Future<void> saveCheckboxStates(String uid) async {
    await FirebaseFirestore.instance
        .collection('skill_analysis_selections')
        .doc(uid)
        .set({
      'high_priority_checked': highPriorityChecked,
      'low_priority_checked': lowPriorityChecked,
      'technical_skills_checked': technicalSkillsChecked,
      'soft_skills_checked': softSkillsChecked,
    }, SetOptions(merge: true));
  }

  Future<void> saveSkillsToImprove() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not logged in.')),
        );
        return;
      }

      final data = {
        'uid': user.uid,
        'timestamp': DateTime.now().toIso8601String(),
        'technical_skills': missingTechnicalSkills,
        'technical_skills_checked': technicalSkillsChecked,
        'soft_skills': missingSoftSkills,
        'soft_skills_checked': softSkillsChecked,
        'high_priority_gaps': highPriorityGaps,
        'high_priority_checked': highPriorityChecked,
        'low_priority_gaps': lowPriorityGaps,
        'low_priority_checked': lowPriorityChecked,
      };

      await FirebaseFirestore.instance
          .collection('skills_to_improve')
          .doc(user.uid)
          .set(data, SetOptions(merge: false));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selection saved successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save selection')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skill Analysis'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Analysis',
            onPressed: () => loadAnalysis(forceRefresh: true),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
          ? Center(child: Text(errorMessage, style: const TextStyle(fontSize: 16, color: color1)))
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Choose Skills to Enhance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  color: color2, // Vibrant blue for titles
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ExpansionTile(
                    title: const Text(
                      "🎓 Education Gap",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color2, // Vibrant blue for titles
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          educationGap,
                          style: const TextStyle(color: color1), // Deep blue for body text
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text(
                      "📋 Other Gaps",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color2, // Vibrant blue for titles
                      ),
                    ),
                    children: [
                      ExpansionTile(
                        title: const Text(
                          "High Priority Gaps",
                          style: TextStyle(color: color2), // Vibrant blue for titles
                        ),
                        children: [
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: highPriorityGaps.length,
                            itemBuilder: (context, index) => CheckboxListTile(
                              title: Text(
                                highPriorityGaps[index],
                                style: const TextStyle(color: color1), // Deep blue for body text
                              ),
                              value: highPriorityChecked[index],
                              onChanged: (bool? value) {
                                setState(() {
                                  highPriorityChecked[index] = value ?? false;
                                });
                                saveCheckboxStates(FirebaseAuth.instance.currentUser!.uid);
                              },
                            ),
                          ),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text(
                          "Low Priority Gaps",
                          style: TextStyle(color: color2), // Vibrant blue for titles
                        ),
                        children: [
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: lowPriorityGaps.length,
                            itemBuilder: (context, index) => CheckboxListTile(
                              title: Text(
                                lowPriorityGaps[index],
                                style: const TextStyle(color: color1), // Deep blue for body text
                              ),
                              value: lowPriorityChecked[index],
                              onChanged: (bool? value) {
                                setState(() {
                                  lowPriorityChecked[index] = value ?? false;
                                });
                                saveCheckboxStates(FirebaseAuth.instance.currentUser!.uid);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text(
                      "❌ Missing Skills",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color2, // Vibrant blue for titles
                      ),
                    ),
                    children: [
                      ExpansionTile(
                        title: const Text(
                          "Technical Skills",
                          style: TextStyle(color: color2), // Vibrant blue for titles
                        ),
                        children: [
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: missingTechnicalSkills.length,
                            itemBuilder: (context, index) => CheckboxListTile(
                              title: Text(
                                missingTechnicalSkills[index],
                                style: const TextStyle(color: color1), // Deep blue for body text
                              ),
                              value: technicalSkillsChecked[index],
                              onChanged: (bool? value) {
                                setState(() {
                                  technicalSkillsChecked[index] = value ?? false;
                                });
                                saveCheckboxStates(FirebaseAuth.instance.currentUser!.uid);
                              },
                            ),
                          ),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text(
                          "Soft Skills",
                          style: TextStyle(color: color2), // Vibrant blue for titles
                        ),
                        children: [
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: missingSoftSkills.length,
                            itemBuilder: (context, index) => CheckboxListTile(
                              title: Text(
                                missingSoftSkills[index],
                                style: const TextStyle(color: color1), // Deep blue for body text
                              ),
                              value: softSkillsChecked[index],
                              onChanged: (bool? value) {
                                setState(() {
                                  softSkillsChecked[index] = value ?? false;
                                });
                                saveCheckboxStates(FirebaseAuth.instance.currentUser!.uid);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Save Skills to Improve'),
                    onPressed: saveSkillsToImprove,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.school),
                    label: const Text('Find Courses to Improve'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CourseSuggestionsPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}