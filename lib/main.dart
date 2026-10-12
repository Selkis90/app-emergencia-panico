import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/emergencia_provider.dart';
import 'providers/premium_provider.dart';
import 'providers/proteccion_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AlertaYaApp());
}

class AlertaYaApp extends StatelessWidget {
  const AlertaYaApp({super.key, this.provider, this.premium});

  /// Permiten inyectar providers en las pruebas.
  final EmergenciaProvider? provider;
  final PremiumProvider? premium;

  static const rojo = Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EmergenciaProvider>(
          create: (_) => provider ?? (EmergenciaProvider()..cargar()),
        ),
        ChangeNotifierProvider<PremiumProvider>(
          create: (_) => premium ?? PremiumProvider(),
        ),
        ChangeNotifierProvider<ProteccionProvider>(
          create: (ctx) => ProteccionProvider(ctx.read<EmergenciaProvider>()),
        ),
      ],
      child: MaterialApp(
        title: 'AlertaYa',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: rojo, primary: rojo),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: rojo,
            foregroundColor: Colors.white,
            centerTitle: true,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
