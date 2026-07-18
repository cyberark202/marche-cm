// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'Firebase is only configured for web on the Admin console '
      '(platform: $defaultTargetPlatform).',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBzCpx92PnNHNgQBWmqIKgAM29JXI0G_ws',
    appId: '1:355585940733:web:6dd74d5666cab0acb5b294',
    messagingSenderId: '355585940733',
    projectId: 'marche-cm',
    authDomain: 'marche-cm.firebaseapp.com',
    storageBucket: 'marche-cm.firebasestorage.app',
    measurementId: 'G-9JLTN5Z60P',
  );
}
