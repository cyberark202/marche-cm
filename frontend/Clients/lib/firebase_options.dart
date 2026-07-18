// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'Firebase iOS is not configured for the Clients app yet. '
          'Register the iOS app in the Firebase console and add '
          'GoogleService-Info.plist, then fill the ios FirebaseOptions.',
        );
      default:
        throw UnsupportedError(
          'Firebase is not configured for this platform (Clients app).',
        );
    }
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

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCOFtUk82Mf-ku8tWjCl74vKGbalTAwids',
    appId: '1:355585940733:android:a0e6e19a1818ff1cb5b294',
    messagingSenderId: '355585940733',
    projectId: 'marche-cm',
    storageBucket: 'marche-cm.firebasestorage.app',
  );
}
