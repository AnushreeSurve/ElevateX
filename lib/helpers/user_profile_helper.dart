import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

Future<void> createUserProfile({
  required String uid,
  required String name,
  required String gmail,
  required String otherEmail,
}) async {
  if (kDebugMode) print('Creating user profile for UID: $uid');
  // If gmail is empty and other_email is a Gmail address, use it as the gmail
  final effectiveGmail = gmail.isNotEmpty ? gmail : (otherEmail.contains('@gmail.com') ? otherEmail : '');
  final userData = {
    'name': name,
    'gmail': effectiveGmail,
    'gmail_verified': effectiveGmail.isNotEmpty ? false : null,
    'other_email': otherEmail,
    'createdAt': FieldValue.serverTimestamp(),
  };
  if (kDebugMode) print('User data to store: $userData');
  try {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(userData, SetOptions(merge: true));
    if (kDebugMode) print('User profile created successfully');
    // Verify the document was created
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      if (kDebugMode) print('Verified: User document exists with data: ${doc.data()}');
    } else {
      if (kDebugMode) print('Error: User document was not created');
      throw Exception('User document was not created');
    }
  } catch (e) {
    if (kDebugMode) print('Failed to create user profile: $e');
    throw Exception('Failed to create user profile: $e');
  }
}