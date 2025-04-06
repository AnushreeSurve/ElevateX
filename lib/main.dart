import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'app_theme.dart'; // Import the new theme file
import 'home_page.dart';
import 'questions_page.dart';
import 'login_page.dart';
import 'resume.dart';
import 'helpers/user_profile_helper.dart'; // Import the new helper

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity, // Use Play Integrity for Android
    appleProvider: AppleProvider.deviceCheck,       // Use DeviceCheck for iOS
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login App',
      theme: appTheme(), // Apply the custom theme globally
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<bool> _hasSubmittedSurvey(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('udata').doc(uid).get();
    return doc.exists;
  }

  Future<bool> _hasCompletedResume(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('resume').doc(uid).get();
    return doc.exists;
  }

  Future<void> _ensureUserProfile(User user) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      // If the user document doesn't exist, create it with default values
      await createUserProfile(
        uid: user.uid,
        name: user.displayName ?? '',
        gmail: '',
        otherEmail: user.email ?? '',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoginPage();
        }

        final user = snapshot.data!;
        final isNewUser = user.metadata.creationTime == user.metadata.lastSignInTime;

        // Ensure the user profile exists
        return FutureBuilder<void>(
          future: _ensureUserProfile(user),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            if (profileSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Text('Error creating user profile: ${profileSnapshot.error}'),
                ),
              );
            }

            return FutureBuilder<List<bool>>(
              future: Future.wait([
                _hasSubmittedSurvey(user.uid),
                _hasCompletedResume(user.uid),
              ]),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }

                final surveyDone = snapshot.data![0];
                final resumeDone = snapshot.data![1];

                if (isNewUser && !surveyDone) return const QuestionsPage();
                if (isNewUser && !resumeDone) return const ResumePage();

                return const HomePage();
              },
            );
          },
        );
      },
    );
  }
}