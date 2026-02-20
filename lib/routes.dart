import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/reading_screen.dart';
import 'screens/sync_screen.dart';
import 'models/book.dart';

class AppRoutes {
  static const splash = '/';
  static const home = '/home';
  static const settings = '/settings';
  static const reading = '/reading';
  static const sync = '/sync';

  static final routes = <String, WidgetBuilder>{
    splash: (_) {
      return const SplashScreen();
    },
    home: (_) {
      return const HomeScreen();
    },
    settings: (_) => const SettingsScreen(),
    sync: (_) => const SyncScreen(),
  };

  static Route<dynamic>? generateRoute(RouteSettings settings) {
    if (settings.name == reading) {
      final Book? book = settings.arguments is Book ? settings.arguments as Book : null;
      if (book == null) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: const Center(child: Text('Invalid book.')),
          ),
        );
      }
      return MaterialPageRoute(
        builder: (_) => ReadingScreen(book: book),
      );
    }
    return null;
  }
}
