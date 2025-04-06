import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'skill_analysis.dart'; // Import the new page
import 'app_theme.dart'; // Import the theme to access colors

class JDPage extends StatefulWidget {
  const JDPage({super.key});

  @override
  State<JDPage> createState() => _JDPageState();
}

class _JDPageState extends State<JDPage> {
  String summary = '';
  String responsibilities = '';
  String qualifications = '';
  String skills = '';
  String relevance = '';

  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    fetchJD();
  }

  Future<void> fetchJD() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          errorMessage = 'User not logged in.';
          isLoading = false;
        });
        return;
      }

      final doc = await FirebaseFirestore.instance.collection('jd').doc(user.uid).get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          summary = data['summary'] ?? 'Not available';
          responsibilities = (data['responsibilities'] is List)
              ? (data['responsibilities'] as List).join('\n')
              : data['responsibilities'] ?? 'Not available';
          qualifications = (data['qualifications'] is List)
              ? (data['qualifications'] as List).join('\n')
              : data['qualifications'] ?? 'Not available';
          skills = (data['skills'] is List)
              ? (data['skills'] as List).join('\n')
              : data['skills'] ?? 'Not available';
          relevance = data['relevance'] ?? 'Not available';
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'No JD found. Please generate one from the Home page.';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading JD: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Description'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
          ? Center(child: Text(errorMessage, style: const TextStyle(fontSize: 16, color: color1)))
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ExpansionTile(
              title: const Text(
                "📄 Job Summary",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color2, // Vibrant blue for titles
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    summary,
                    style: const TextStyle(color: color1), // Deep blue for body text
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text(
                "🛠 Responsibilities",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color2, // Vibrant blue for titles
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    responsibilities,
                    style: const TextStyle(color: color1), // Deep blue for body text
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text(
                "🎓 Qualifications",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color2, // Vibrant blue for titles
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    qualifications,
                    style: const TextStyle(color: color1), // Deep blue for body text
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text(
                "💡 Skills",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color2, // Vibrant blue for titles
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    skills,
                    style: const TextStyle(color: color1), // Deep blue for body text
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text(
                "📈 Role Relevance",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color2, // Vibrant blue for titles
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    relevance,
                    style: const TextStyle(color: color1), // Deep blue for body text
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.analytics),
              label: const Text('Analyze Missing Skills'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SkillAnalysisPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}