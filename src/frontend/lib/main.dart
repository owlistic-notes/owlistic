import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart'; // Add this import for GoRouter
import 'core/router.dart';
import 'core/providers.dart';
import 'core/theme.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Initialize the application
  runApp(const ThinkStackApp());
}

class ThinkStackApp extends StatefulWidget {
  const ThinkStackApp({super.key});

  @override
  State<ThinkStackApp> createState() => _ThinkStackAppState();
}

class _ThinkStackAppState extends State<ThinkStackApp> {
  late AuthProvider authProvider;
  late GoRouter router; // Now GoRouter will be properly recognized
  
  @override
  void initState() {
    super.initState();
    authProvider = AuthProvider();
    authProvider.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ...appProviders,
      ],
      child: Builder(
        builder: (context) {
          // Access the theme provider after it's been created
          final themeProvider = Provider.of<ThemeProvider>(context);
          
          // Create the router with the auth provider
          final router = AppRouter.createRouter(authProvider);
          
          return MaterialApp.router(
            title: 'ThinkStack',
            theme: AppTheme.getThemeData(ThemeMode.light),
            darkTheme: AppTheme.getThemeData(ThemeMode.dark),
            themeMode: themeProvider.themeMode,
            routerConfig: router,
            debugShowCheckedModeBanner: false,
          );
        }
      ),
    );
  }
}
