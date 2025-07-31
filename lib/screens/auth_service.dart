import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

// Custom exception for better error handling in the UI
class GoogleSignInException implements Exception {
  final String message;
  GoogleSignInException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> _addUserToFirestore(User user, {String? displayName}) async {
    final userDoc = _firestore.collection('Users').doc(user.uid);
    final snapshot = await userDoc.get();

    if (!snapshot.exists) {
      await userDoc.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': displayName ?? user.displayName,
        'photoURL': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Failed to sign in with Email & Password: ${e.message}');
      return null;
    }
  }

  Future<User?> signUpWithEmail(String email, String password, String displayName) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (result.user != null) {
        await result.user!.updateDisplayName(displayName);
        await _addUserToFirestore(result.user!, displayName: displayName);
      }
      return result.user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Failed to sign up with Email & Password: ${e.message}');
      return null;
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User canceled the sign-in flow.
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential result = await _auth.signInWithCredential(credential);

      if (result.user != null) {
        await _addUserToFirestore(result.user!);
      }
      return result.user;
    } on PlatformException catch (e) {
      // This is a common error for misconfiguration.
      debugPrint('Google Sign-In PlatformException: ${e.code} - ${e.message}');
      throw GoogleSignInException(
          'Google Sign-In Error. Please check your app configuration (e.g., SHA-1 fingerprint in Firebase) and network connection. Error code: ${e.code}');
    } on FirebaseAuthException catch (e) {
      debugPrint('Google Sign-In FirebaseAuthException: ${e.code} - ${e.message}');
      throw GoogleSignInException('Firebase authentication failed. ${e.message}');
    } catch (e) {
      debugPrint('An unexpected error occurred during Google Sign-In: $e');
      throw GoogleSignInException('An unexpected error occurred. Please try again.');
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      debugPrint('Error signing out: $e');
    }
  }
}
