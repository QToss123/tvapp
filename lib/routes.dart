import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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
      debugPrint('🗺️ [ROUTES] Building SplashScreen widget');
      return const SplashScreen();
    },
    home: (_) {
      debugPrint('🗺️ [ROUTES] Building HomeScreen widget');
      debugPrint('🗺️ [ROUTES] This creates a NEW HomeScreen instance');
      return const HomeScreen();
    },
    settings: (_) => const SettingsScreen(),
    sync: (_) => const SyncScreen(),
  };

  static Route<dynamic>? generateRoute(RouteSettings settings) {
    if (settings.name == reading) {
      final Book book = settings.arguments as Book;
      return MaterialPageRoute(
        builder: (_) => ReadingScreen(book: book),
      );
    }
    return null;
  }
}
