import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'core/router.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Initialize the application
  runApp(const ThinkStackApp());
}

class ThinkStackApp extends StatelessWidget {
  const ThinkStackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: appProviders, // Use the providers defined in core/providers.dart
      child: MaterialApp.router(
        title: 'ThinkStack',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          // Add more theme customization here
        ),
        routerConfig: AppRouter.router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
