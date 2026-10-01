import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/api_client.dart';
import 'core/session.dart';
import 'features/auth/auth_screen.dart';
import 'features/shell.dart';
import 'shared/ui.dart';

void main() => runApp(ChangeNotifierProvider(
    create: (_) => Session(ApiClient())..initialize(), child: const JolApp()));

class JolApp extends StatelessWidget {
  const JolApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'JOL Cargo',
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(
              seedColor: brandBlue, primary: brandBlue, surface: Colors.white),
          appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: ink,
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFECF0F6))),
          ),
          navigationBarTheme: const NavigationBarThemeData(
              backgroundColor: Colors.white,
              indicatorColor: Color(0xFFE8F2FF),
              height: 68),
          dividerTheme: const DividerThemeData(color: Color(0xFFECF0F6)),
          inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE1E8F2)))),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)))),
        ),
        home: Consumer<Session>(builder: (context, session, _) {
          if (session.loading) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (session.restoreError != null) {
            return Scaffold(
                body: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                  padding: const EdgeInsets.all(24),
                  child:
                      Text(session.restoreError!, textAlign: TextAlign.center)),
              FilledButton(
                  onPressed: session.initialize,
                  child: const Text('Повторить')),
              TextButton(
                  onPressed: session.logout, child: const Text('Войти заново'))
            ])));
          }
          // Reset navigation and screen state when switching accounts.
          return session.user == null
              ? const AuthScreen()
              : Navigator(
                  key: ValueKey(session.userId),
                  onGenerateRoute: (_) =>
                      MaterialPageRoute(builder: (_) => const AppShell()));
        }),
      );
}
