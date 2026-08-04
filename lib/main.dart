import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'services/diagnostic_log_service.dart';
import 'services/recognition_service.dart';
import 'utils/constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(DiagnosticLogService.initialize());
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(DiagnosticLogService.write(
      'flutter-framework',
      details.exception,
      details.stack,
    ));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(DiagnosticLogService.write('flutter-platform', error, stack));
    return true;
  };
  runZonedGuarded(
    () {
      unawaited(RecognitionService.initialize());
      runApp(const ProviderScope(child: ScreenAnswerApp()));
    },
    (error, stack) {
      unawaited(DiagnosticLogService.write('flutter-zone', error, stack));
    },
  );
}

class ScreenAnswerApp extends StatelessWidget {
  const ScreenAnswerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: const Color(0xFFF7F8FA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F8FA),
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Color(0xFF666666)),
          titleTextStyle: TextStyle(color: Color(0xFF333333), fontSize: 18, fontWeight: FontWeight.w600),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
