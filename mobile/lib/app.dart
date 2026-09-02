import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/license_page.dart';
import 'pages/qr_scanner_page.dart';
import 'pages/review_page.dart';
import 'pages/settings_page.dart';

class WordPetApp extends StatelessWidget {
  const WordPetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '单词桌宠',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFD84D)),
        scaffoldBackgroundColor: const Color(0xFFFFFDF2),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomePage(),
        '/settings': (_) => const SettingsPage(),
        '/review': (_) => const ReviewPage(),
        '/license': (_) => const AboutLicensePage(),
        '/qr': (_) => const QrScannerPage(),
      },
    );
  }
}
