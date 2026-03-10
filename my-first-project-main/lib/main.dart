import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';
import 'services/theme_provider.dart';
import 'services/profile_photo_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Load persisted theme preference before painting
  await ThemeProvider.instance.load();
  await ProfilePhotoService.instance.loadProfilePhoto();
  // Initialize local notifications + background budget check task
  await NotificationService.init();
  runApp(const StudentMoneyManagerApp());
}

class StudentMoneyManagerApp extends StatelessWidget {
  const StudentMoneyManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder re-builds whenever ThemeProvider notifies (toggle).
    return ListenableBuilder(
      listenable: ThemeProvider.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Student Money Manager',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeProvider.instance.themeMode,
          home: const SplashScreen(),
        );
      },
    );
  }
}

/// Auth gate: listens to Firebase auth state and routes accordingly.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const DashboardScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
