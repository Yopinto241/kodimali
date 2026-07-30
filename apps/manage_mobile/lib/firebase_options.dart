import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Firebase web is not configured.');
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => throw UnsupportedError(
        'Firebase is not configured for this platform.',
      ),
    };
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAatbW7nC8irm4J2qCW_ORhf7uzqmpSZCI',
    appId: '1:561145643946:android:0bd932972298494890a1d3',
    messagingSenderId: '561145643946',
    projectId: 'kodimali',
    storageBucket: 'kodimali.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAcZnv6nvECCN7b6BVkSqBIVT1ZcqBHWi8',
    appId: '1:561145643946:ios:f6b010c0e953454f90a1d3',
    messagingSenderId: '561145643946',
    projectId: 'kodimali',
    storageBucket: 'kodimali.firebasestorage.app',
    iosBundleId: 'co.kodimali.agentMobile',
  );
}
