import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/api_client.dart';
import 'core/session.dart';
import 'features/auth/auth_screen.dart';
import 'features/shell.dart';
import 'shared/ui.dart';

void main() => runApp(ChangeNotifierProvider(create: (_) => Session(ApiClient())..initialize(), child: const JolApp()));

class JolApp extends StatelessWidget {
  const JolApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JOL Cargo', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: green, primary: green, surface: Colors.white),
      appBarTheme: const AppBarTheme(backgroundColor: cream, foregroundColor: ink, centerTitle: false),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFD8E0DB)))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    ),
    home: Consumer<Session>(builder: (context, session, _) {
      if (session.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      if (session.restoreError != null) return Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Padding(padding: const EdgeInsets.all(24), child: Text(session.restoreError!, textAlign: TextAlign.center)), FilledButton(onPressed: session.initialize, child: const Text('Повторить')), TextButton(onPressed: session.logout, child: const Text('Войти заново'))])));
      // Reset navigation and screen state when switching accounts.
      return session.user == null ? const AuthScreen() : Navigator(key: ValueKey(session.userId), onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const AppShell()));
    }),
  );
}
