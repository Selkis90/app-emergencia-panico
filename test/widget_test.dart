import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alertaya/main.dart';
import 'package:alertaya/providers/premium_provider.dart';

void main() {
  testWidgets('La pantalla principal muestra el botón SOS', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      AlertaYaApp(premium: PremiumProvider(conectarTienda: false)),
    );
    // La animación del botón es infinita: no usar pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('AlertaYa'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
    expect(find.byIcon(Icons.contacts), findsOneWidget);
  });
}
