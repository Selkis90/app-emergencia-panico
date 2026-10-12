import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/premium_provider.dart';

/// Lista de funciones Premium (se usa también en otras pantallas).
class FuncionPremium {
  final IconData icono;
  final String titulo;
  final String detalle;

  const FuncionPremium(this.icono, this.titulo, this.detalle);
}

const funcionesPremium = [
  FuncionPremium(
    Icons.share_location,
    'Ubicación en vivo',
    'Después del S.O.S., tus contactos reciben tu ubicación actualizada por SMS cada pocos minutos.',
  ),
  FuncionPremium(
    Icons.timer_outlined,
    'Modo "Llegué bien"',
    'Activa un temporizador cuando salgas. Si no confirmas que llegaste, la alerta se envía sola.',
  ),
  FuncionPremium(
    Icons.campaign,
    'Sirena de emergencia',
    'Alarma a todo volumen para pedir ayuda a quien esté cerca o espantar a un agresor.',
  ),
  FuncionPremium(
    Icons.flashlight_on,
    'Linterna S.O.S.',
    'La linterna parpadea en código S.O.S. para que te encuentren de noche.',
  ),
  FuncionPremium(
    Icons.perm_media,
    'Foto, video y audio',
    'Durante la emergencia toma una foto, graba video o audio y envíalo por WhatsApp con tu ubicación.',
  ),
];

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PremiumProvider>();
    final mensaje = p.mensaje;

    return Scaffold(
      appBar: AppBar(title: const Text('AlertaYa Premium')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.amber.shade100,
              ),
              child: Icon(Icons.workspace_premium, size: 56, color: Colors.amber.shade800),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            p.esPremium ? '¡Ya eres Premium! ⭐' : 'Más protección para ti y los tuyos',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            p.esPremium
                ? 'Todas las funciones están activas. Gracias por apoyar AlertaYa.'
                : 'Pago único, sin suscripción. El botón S.O.S., el SMS y WhatsApp siguen siendo gratis siempre.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 20),
          for (final f in funcionesPremium)
            Card(
              child: ListTile(
                leading: Icon(f.icono, color: Theme.of(context).colorScheme.primary, size: 32),
                title: Text(f.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(f.detalle),
                trailing: p.esPremium
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.lock_outline),
              ),
            ),
          const SizedBox(height: 20),
          if (mensaje != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(mensaje, textAlign: TextAlign.center),
            ),
          if (!p.esPremium) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: Colors.amber.shade800,
              ),
              onPressed: p.procesando ? null : p.comprar,
              icon: p.procesando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.star),
              label: Text(
                p.precio == null ? 'Obtener Premium' : 'Obtener Premium · ${p.precio}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: p.procesando ? null : p.restaurar,
              child: const Text('Ya lo compré: restaurar compra'),
            ),
            if (!p.tiendaDisponible)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'La compra se activa cuando instalas AlertaYa desde Google Play.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ],
          if (PremiumProvider.modoPrueba)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                '🧪 Versión de prueba: Premium activado con PREMIUM_PRUEBA.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.deepOrange),
              ),
            ),
        ],
      ),
    );
  }
}

/// Muestra la pantalla Premium. Devuelve true si el usuario ya es Premium.
Future<bool> abrirPremium(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
  if (!context.mounted) return false;
  return context.read<PremiumProvider>().esPremium;
}
