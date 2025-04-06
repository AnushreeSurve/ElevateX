import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'helpers/user_profile_helper.dart'; // Import the new helper
import 'questions_page.dart'; // Import QuestionsPage

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final nameController = TextEditingController();
  final otherEmailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLogin = true;
  bool isLoading = false;
  String errorMessage = '';
  bool obscurePassword = true; // For password hide/show
  bool showGmailSignIn = false; // To show Gmail sign-in fields
  bool gmailVerified = false; // To track Gmail verification status

  @override
  void dispose() {
    nameController.dispose();
    otherEmailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkGmailVerification(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists && doc.data()!['gmail'] != null && doc.data()!['gmail_verified'] == false) {
      setState(() {
        showGmailSignIn = true;
        errorMessage = 'Please sign in with your Gmail to verify your email.';
      });
    } else if (doc.exists && doc.data()!['gmail_verified'] == true) {
      setState(() {
        gmailVerified = true;
        showGmailSignIn = false;
      });
    }
  }

  Future<void> _submit() async {
    if (kDebugMode) print('Submit button pressed: ${isLogin ? "Login" : "Signup"}');
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      if (!isLogin) {
        final name = nameController.text.trim();
        if (name.isEmpty || name.length < 2) {
          throw Exception('Please enter a valid name (at least 2 characters)');
        }
        if (otherEmailController.text.isNotEmpty && !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(otherEmailController.text)) {
          throw Exception('Invalid email format for Email Address');
        }
      }
      if (passwordController.text.length < 6) {
        throw Exception('Password must be at least 6 characters');
      }

      if (isLogin) {
        if (kDebugMode) print('Logging in with: ${otherEmailController.text}');
        final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: otherEmailController.text.trim(),
          password: passwordController.text,
        );
        await _checkGmailVerification(userCredential.user!.uid);
        if (kDebugMode) print('Login successful');
        // Let AuthGate handle redirection to HomePage
      } else {
        String emailToUse = otherEmailController.text.trim();
        if (emailToUse.isEmpty) {
          throw Exception('Email address is required');
        }

        if (kDebugMode) print('Signing up with: $emailToUse');
        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailToUse,
          password: passwordController.text,
        );
        User? user = userCredential.user;
        if (user == null) {
          throw Exception('User creation failed');
        }

        if (kDebugMode) print('User created with UID: ${user.uid}');

        // Wait for auth state to update
        await FirebaseAuth.instance.authStateChanges().firstWhere((user) => user != null);
        if (kDebugMode) print('Auth state updated for UID: ${user.uid}');

        // Update user profile with signup data
        if (kDebugMode) print('Updating user profile for UID: ${user.uid}');
        try {
          await createUserProfile(
            uid: user.uid,
            name: nameController.text.trim(),
            gmail: '', // No Gmail-specific field
            otherEmail: emailToUse,
          );
          if (kDebugMode) print('User profile updated successfully');
        } catch (e) {
          if (kDebugMode) print('Failed to update user profile: $e');
          setState(() {
            errorMessage = 'Failed to update user profile: $e';
            isLoading = false;
          });
          return; // Stop the signup process if the user profile can't be updated
        }

        // Redirect to QuestionsPage after successful signup
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const QuestionsPage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) print('FirebaseAuthException: ${e.message}');
      setState(() => errorMessage = e.message ?? 'Authentication error');
    } catch (e) {
      if (kDebugMode) print('Error: $e');
      setState(() => errorMessage = e.toString());
    } finally {
      if (errorMessage.isEmpty && !showGmailSignIn && isLogin) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Image.asset(
                'assets/circleLogo.png',
                height: 100,
              ),
              const SizedBox(height: 16),
              Text(
                'SkillSetGo',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: color2,
                ),
              ),
              const SizedBox(height: 24),
              if (isLogin) ...[
                TextField(
                  controller: otherEmailController,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () {
                        setState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: obscurePassword,
                ),
              ],
              if (!isLogin && !showGmailSignIn) ...[
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: otherEmailController,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () {
                        setState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: obscurePassword,
                ),
              ],
              const SizedBox(height: 20),
              if (errorMessage.isNotEmpty)
                Text(
                  errorMessage,
                  style: const TextStyle(color: color1),
                ),
              if (!showGmailSignIn || gmailVerified)
                ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(isLogin ? 'Login' : 'Sign Up'),
                ),
              TextButton(
                onPressed: () {
                  setState(() {
                    isLogin = !isLogin;
                    errorMessage = '';
                    otherEmailController.clear(); // Clear on toggle
                    showGmailSignIn = false;
                    gmailVerified = false;
                  });
                },
                child: Text(
                  isLogin
                      ? "Don't have an account? Sign Up"
                      : "Already have an account? Login",
                  style: const TextStyle(color: color2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
