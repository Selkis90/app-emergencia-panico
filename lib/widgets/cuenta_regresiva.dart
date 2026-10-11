import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Diálogo de cuenta regresiva antes de enviar la alerta (evita envíos
/// accidentales). Devuelve true si se debe enviar, false si se canceló.
Future<bool> mostrarCuentaRegresiva(BuildContext context, int segundos) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CuentaRegresiva(segundos: segundos),
  );
  return r ?? false;
}

class _CuentaRegresiva extends StatefulWidget {
  const _CuentaRegresiva({required this.segundos});

  final int segundos;

  @override
  State<_CuentaRegresiva> createState() => _CuentaRegresivaState();
}

class _CuentaRegresivaState extends State<_CuentaRegresiva> {
  late int _restante = widget.segundos;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_restante <= 1) {
        t.cancel();
        Navigator.of(context).pop(true);
        return;
      }
      HapticFeedback.heavyImpact();
      setState(() => _restante--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _cerrar(bool enviar) {
    _timer?.cancel();
    Navigator.of(context).pop(enviar);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFB71C1C),
      title: const Text(
        '🆘 Enviando alerta S.O.S.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$_restante',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 84,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            'Se enviará a tus contactos de emergencia.\n¿Fue un error? Toca CANCELAR.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFB71C1C),
              ),
              onPressed: () => _cerrar(false),
              child: const Text(
                'CANCELAR',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _cerrar(true),
            child: const Text(
              'Enviar ya',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
