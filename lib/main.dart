import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'services/recognition_service.dart';
import 'utils/constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  RecognitionService.initialize();
  runApp(const ProviderScope(child: ScreenAnswerApp()));
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
