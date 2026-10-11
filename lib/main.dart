import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/emergencia_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.provider});

  /// Permite inyectar un provider en las pruebas.
  final EmergenciaProvider? provider;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EmergenciaProvider>(
      create: (_) => provider ?? (EmergenciaProvider()..cargar()),
      child: MaterialApp(
        title: 'Emergencia',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFD32F2F),
            primary: const Color(0xFFD32F2F),
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFD32F2F),
            foregroundColor: Colors.white,
            centerTitle: true,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
