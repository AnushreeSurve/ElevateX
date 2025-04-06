import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart'; // Import the theme to access colors
import 'schedule_courses.dart';

class CourseSuggestionsPage extends StatefulWidget {
  const CourseSuggestionsPage({super.key});

  @override
  State<CourseSuggestionsPage> createState() => _CourseSuggestionsPageState();
}

class _CourseSuggestionsPageState extends State<CourseSuggestionsPage> {
  Map<String, Map<String, List<Map<String, dynamic>>>> courseSuggestions = {};
  Map<String, Map<String, List<bool>>> courseSelections = {};
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    fetchSelectedSkillsAndCourses();
  }

  Future<void> fetchSelectedSkillsAndCourses() async {
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

      // Fetch selected skills from skills_to_improve
      final skillsDoc = await FirebaseFirestore.instance
          .collection('skills_to_improve')
          .doc(user.uid)
          .get();

      if (!skillsDoc.exists) {
        setState(() {
          errorMessage = 'No skills selected for improvement.';
          isLoading = false;
        });
        return;
      }

      final skillsData = skillsDoc.data()!;
      Map<String, Map<String, List<String>>> selectedSkills = {
        'Technical Skills': {},
        'Soft Skills': {},
        'High Priority Gaps': {},
        'Low Priority Gaps': {},
      };

      // Extract selected skills
      final technicalSkills = List<String>.from(skillsData['technical_skills'] ?? []);
      final technicalChecked = List<bool>.from(skillsData['technical_skills_checked'] ?? []);
      for (int i = 0; i < technicalSkills.length; i++) {
        if (technicalChecked[i]) {
          selectedSkills['Technical Skills']![technicalSkills[i]] = [];
        }
      }

      final softSkills = List<String>.from(skillsData['soft_skills'] ?? []);
      final softChecked = List<bool>.from(skillsData['soft_skills_checked'] ?? []);
      for (int i = 0; i < softSkills.length; i++) {
        if (softChecked[i]) {
          selectedSkills['Soft Skills']![softSkills[i]] = [];
        }
      }

      final highPriorityGaps = List<String>.from(skillsData['high_priority_gaps'] ?? []);
      final highPriorityChecked = List<bool>.from(skillsData['high_priority_checked'] ?? []);
      for (int i = 0; i < highPriorityGaps.length; i++) {
        if (highPriorityChecked[i]) {
          final skill = highPriorityGaps[i].replaceAll('JD requires: ', '').split(';')[0].trim();
          selectedSkills['High Priority Gaps']![skill] = [];
        }
      }

      final lowPriorityGaps = List<String>.from(skillsData['low_priority_gaps'] ?? []);
      final lowPriorityChecked = List<bool>.from(skillsData['low_priority_checked'] ?? []);
      for (int i = 0; i < lowPriorityGaps.length; i++) {
        if (lowPriorityChecked[i]) {
          final skill = lowPriorityGaps[i].replaceAll('JD requires: ', '').split(';')[0].trim();
          selectedSkills['Low Priority Gaps']![skill] = [];
        }
      }

      // Call Cloud Function to search for courses
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south2')
          .httpsCallable('search_courses');
      final response = await callable.call({'skills': selectedSkills});

      if (response.data['status'] == 'success') {
        // Safely convert the response data to Map<String, dynamic>
        final rawData = response.data['result'] as Map;
        final data = rawData.map((key, value) => MapEntry(
          key.toString(),
          (value as Map).map((k, v) => MapEntry(
            k.toString(),
            (v as List).map((course) => (course as Map).map((ck, cv) => MapEntry(ck.toString(), cv))).toList(),
          )),
        ));

        setState(() {
          courseSuggestions = data.map((category, skills) => MapEntry(
            category,
            skills.map((skill, courses) => MapEntry(
              skill,
              courses.map((course) => course as Map<String, dynamic>).toList(),
            )),
          ));

          // Initialize checkbox states
          courseSelections = courseSuggestions.map((category, skills) => MapEntry(
            category,
            skills.map((skill, courses) => MapEntry(
              skill,
              List<bool>.filled(courses.length, false),
            )),
          ));
        });
      } else {
        throw Exception(response.data['error']);
      }

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading course suggestions: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  Future<void> saveSelectedCourses() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not logged in.')),
        );
        return;
      }

      // Construct the data to save
      Map<String, Map<String, List<Map<String, dynamic>>>> selectedCourses = {
        'technical_skills': {},
        'soft_skills': {},
        'high_priority_gaps': {},
        'low_priority_gaps': {},
      };

      courseSuggestions.forEach((category, skills) {
        String categoryKey = category == 'Technical Skills'
            ? 'technical_skills'
            : category == 'Soft Skills'
            ? 'soft_skills'
            : category == 'High Priority Gaps'
            ? 'high_priority_gaps'
            : 'low_priority_gaps';

        skills.forEach((skill, courses) {
          List<Map<String, dynamic>> selected = [];
          final selections = courseSelections[category]![skill]!;
          for (int i = 0; i < courses.length; i++) {
            if (selections[i]) {
              selected.add(courses[i]);
            }
          }
          if (selected.isNotEmpty) {
            selectedCourses[categoryKey]![skill] = selected;
          }
        });
      });

      final data = {
        'uid': user.uid,
        'timestamp': DateTime.now().toIso8601String(),
        'technical_skills': selectedCourses['technical_skills'],
        'soft_skills': selectedCourses['soft_skills'],
        'high_priority_gaps': selectedCourses['high_priority_gaps'],
        'low_priority_gaps': selectedCourses['low_priority_gaps'],
      };

      await FirebaseFirestore.instance
          .collection('selected_courses')
          .doc(user.uid)
          .set(data, SetOptions(merge: false));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Courses saved successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save courses')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhance Your Skills: Course Recommendations'),
        centerTitle: true,
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
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Explore Courses to Boost Your Skills',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  color: color2, // Vibrant blue for titles
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '* Note: Links are for reference. If a link doesn’t work, search for the course by its name on the specified platform.',
                style: TextStyle(
                  fontSize: 12,
                  color: color4, // Soft purple for notes
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView(
                  children: courseSuggestions.entries.map((categoryEntry) {
                    final category = categoryEntry.key;
                    final skills = categoryEntry.value;

                    if (skills.isEmpty) return const SizedBox.shrink();

                    return ExpansionTile(
                      title: Text(
                        category,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color2, // Vibrant blue for titles
                        ),
                      ),
                      children: skills.entries.map((skillEntry) {
                        final skill = skillEntry.key;
                        final courses = skillEntry.value;
                        final selections = courseSelections[category]![skill]!;

                        return ExpansionTile(
                          title: Text(
                            skill,
                            style: const TextStyle(color: color2), // Vibrant blue for titles
                          ),
                          children: courses.asMap().entries.map((courseEntry) {
                            final index = courseEntry.key;
                            final course = courseEntry.value;

                            return CheckboxListTile(
                              title: Text(
                                '${course['source']}: ${course['title']} - ${course['fee']} - ${course['duration']}',
                                style: const TextStyle(color: color1), // Deep blue for body text
                              ),
                              subtitle: GestureDetector(
                                onTap: () async {
                                  final url = course['link'];
                                  if (await canLaunch(url)) {
                                    await launch(url);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Could not launch $url')),
                                    );
                                  }
                                },
                                child: Text(
                                  course['link'],
                                  style: const TextStyle(
                                    color: color4, // Soft purple for links (subtle text)
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              value: selections[index],
                              onChanged: (bool? value) {
                                setState(() {
                                  selections[index] = value ?? false;
                                });
                              },
                            );
                          }).toList(),
                        );
                      }).toList(),
                    );
                  }).toList()
                    ..add(const SizedBox(height: 16))
                    ..add(
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Save Selected Courses'),
                        onPressed: saveSelectedCourses,
                      ),
                    )
                    ..add(const SizedBox(height: 16)) // Add spacing between buttons
                    ..add(
                      ElevatedButton.icon(
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('Schedule Courses'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ScheduleCoursesPage()),
                          );
                        },
                      ),
                    ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}