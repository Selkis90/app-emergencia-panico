import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/emergencia_provider.dart';
import '../providers/premium_provider.dart';
import '../providers/proteccion_provider.dart';
import '../screens/premium_screen.dart';

/// Tarjeta del modo "Llegué bien" (Premium) para la pantalla principal.
class TarjetaLlegueBien extends StatefulWidget {
  const TarjetaLlegueBien({super.key});

  @override
  State<TarjetaLlegueBien> createState() => _TarjetaLlegueBienState();
}

class _TarjetaLlegueBienState extends State<TarjetaLlegueBien> {
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    // Refresca la cuenta regresiva cada segundo.
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<ProteccionProvider>().temporizadorActivo) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  String _formato(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _iniciar() async {
    final premium = context.read<PremiumProvider>();
    if (!premium.esPremium) {
      await abrirPremium(context);
      return;
    }
    final app = context.read<EmergenciaProvider>();
    if (app.contactosSms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Necesitas al menos un contacto con SMS activado.')),
      );
      return;
    }
    final r = await showDialog<_Eleccion>(
      context: context,
      builder: (_) => const _DialogoTemporizador(),
    );
    if (r == null || !mounted) return;
    await context.read<ProteccionProvider>().iniciarTemporizador(r.duracion, destino: r.destino);
  }

  @override
  Widget build(BuildContext context) {
    final prot = context.watch<ProteccionProvider>();
    final esPremium = context.watch<PremiumProvider>().esPremium;

    if (!prot.temporizadorActivo) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.timer_outlined, color: Colors.indigo),
          title: const Text('Modo "Llegué bien"', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('¿Vas a salir? Si no confirmas que llegaste, se envía la alerta sola.'),
          trailing: esPremium
              ? const Icon(Icons.play_circle_fill, color: Colors.indigo, size: 32)
              : Icon(Icons.workspace_premium, color: Colors.amber.shade800),
          onTap: _iniciar,
        ),
      );
    }

    final destino = prot.destino;
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.timer, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    destino.isEmpty ? 'Llegué bien: activo' : 'Llegué bien: rumbo a $destino',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  _formato(prot.restante),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Si el tiempo llega a cero sin que confirmes, AlertaYa enviará el S.O.S. por SMS a tus contactos.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                    onPressed: prot.llegueBien,
                    icon: const Icon(Icons.check),
                    label: const Text('Llegué bien'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => prot.extenderTemporizador(const Duration(minutes: 15)),
                  child: const Text('+15 min'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Eleccion {
  final Duration duracion;
  final String destino;

  const _Eleccion(this.duracion, this.destino);
}

class _DialogoTemporizador extends StatefulWidget {
  const _DialogoTemporizador();

  @override
  State<_DialogoTemporizador> createState() => _DialogoTemporizadorState();
}

class _DialogoTemporizadorState extends State<_DialogoTemporizador> {
  int _minutos = 30;
  final _destino = TextEditingController();

  @override
  void dispose() {
    _destino.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const opciones = [15, 30, 45, 60, 90, 120];
    return AlertDialog(
      title: const Text('⏱️ Llegué bien'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('¿En cuánto tiempo deberías llegar?'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in opciones)
                ChoiceChip(
                  label: Text(m < 60 ? '$m min' : '${m ~/ 60} h${m % 60 == 0 ? '' : ' ${m % 60}'}'),
                  selected: _minutos == m,
                  onSelected: (_) => setState(() => _minutos = m),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _destino,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: '¿A dónde vas? (opcional)',
              hintText: 'Ej: la casa, el trabajo…',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _Eleccion(Duration(minutes: _minutos), _destino.text),
          ),
          child: const Text('Iniciar'),
        ),
      ],
    );
  }
}
