import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Current user stream for auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Current signed-in user
  User? get currentUser => _auth.currentUser;

  /// Sign in with email and password
  Future<UserCredential> signIn(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthException(e));
    } catch (e) {
      throw Exception('Login failed. Please check your connection and try again.');
    }
  }

  /// Create a new account with email, password, and display name.
  /// Saves a user profile document to Firestore under users/{uid}.
  Future<UserCredential> signUp(
      String email, String password, String name) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user!;

      // Update Firebase Auth display name
      await user.updateDisplayName(name.trim());

      // Save user profile to Firestore (non-blocking — won't fail signup)
      try {
        final userModel = UserModel(
          uid: user.uid,
          name: name.trim(),
          email: email.trim(),
        );
        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(userModel.toMap());
      } catch (firestoreError) {
        // Profile save failed (e.g. Firestore rules) — account still created
        debugPrint('Firestore profile save failed: $firestoreError');
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthException(e));
    } catch (e) {
      throw Exception('Sign up failed. Please check your connection and try again.');
    }
  }

  /// Fetch the current user's profile from Firestore.
  Future<UserModel?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) return UserModel.fromFirestore(doc);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Send password reset email
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Maps Firebase error codes to human-readable messages
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password must be at least 6 characters long.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      case 'invalid-credential':
        return 'Invalid email or password. Please try again.';
      default:
        return e.message ?? 'An unexpected error occurred. Please try again.';
    }
  }
}
