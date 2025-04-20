import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/providers.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'services/api_service.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Initialize API service (loads stored tokens)
  await ApiService.initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ...appProviders,
      ],
      child: Builder(
        builder: (context) {
          final authProvider = Provider.of<AuthProvider>(context);
          final router = AppRouter.createRouter(authProvider);
          
          return Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => MaterialApp.router(
              title: 'ThinkStack',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeProvider.themeMode,
              routerConfig: router,
              debugShowCheckedModeBanner: false,
            ),
          );
        }
      ),
    );
  }
}
