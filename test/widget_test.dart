import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:emergencia/main.dart';

void main() {
  testWidgets('La pantalla principal muestra el botón SOS', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyApp());
    // La animación del botón es infinita: no usar pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Botón de Pánico'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
    expect(find.byIcon(Icons.contacts), findsOneWidget);
  });
}
