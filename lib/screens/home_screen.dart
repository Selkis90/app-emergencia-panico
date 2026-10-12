import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/emergencia_provider.dart';
import '../providers/premium_provider.dart';
import '../providers/proteccion_provider.dart';
import '../services/nativo.dart';
import '../services/ubicacion.dart';
import '../utils/mensajes.dart';
import '../widgets/boton_sos.dart';
import '../widgets/cuenta_regresiva.dart';
import '../widgets/llegue_bien.dart';
import 'ajustes_screen.dart';
import 'contactos_screen.dart';
import 'envio_screen.dart';
import 'premium_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de Ajustes (GPS / permisos) se refresca el estado.
    if (state == AppLifecycleState.resumed) {
      context.read<EmergenciaProvider>().actualizarEstados();
    }
  }

  Future<void> _abrir(Widget pantalla) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));
    if (mounted) context.read<EmergenciaProvider>().actualizarEstados();
  }

  Future<void> _iniciar(TipoAlerta tipo) async {
    if (_ocupado) return;
    final p = context.read<EmergenciaProvider>();

    if (p.contactos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Primero agrega al menos un contacto de emergencia'),
          action: SnackBarAction(
            label: 'AGREGAR',
            onPressed: () => _abrir(const ContactosScreen()),
          ),
        ),
      );
      return;
    }

    setState(() => _ocupado = true);
    try {
      bool continuar;
      if (tipo == TipoAlerta.emergencia) {
        final s = p.ajustes.segundosCuentaRegresiva;
        continuar = s <= 0 ? true : await mostrarCuentaRegresiva(context, s);
      } else {
        continuar = await _confirmar(tipo);
      }
      if (!continuar || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EnvioScreen(tipo: tipo)),
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<bool> _confirmar(TipoAlerta tipo) async {
    final prueba = tipo == TipoAlerta.prueba;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(prueba ? '🧪 Mensaje de prueba' : '✅ Avisar que estás a salvo'),
        content: Text(
          prueba
              ? 'Se enviará un mensaje de PRUEBA a tus contactos para comprobar que todo funciona.'
              : 'Se avisará a tus contactos que ya estás bien y que la alerta queda cancelada.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EmergenciaProvider>();
    final prot = context.watch<ProteccionProvider>();
    final esPremium = context.watch<PremiumProvider>().esPremium;
    final linea = p.ajustes.numeroEmergencias.trim();
    final avisoAutomatico = prot.ultimaAlertaAutomatica;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AlertaYa', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        actions: [
          IconButton(
            tooltip: 'Premium',
            icon: Icon(
              esPremium ? Icons.workspace_premium : Icons.workspace_premium_outlined,
              color: esPremium ? Colors.amber.shade300 : Colors.white,
            ),
            onPressed: () => _abrir(const PremiumScreen()),
          ),
          IconButton(
            tooltip: 'Contactos',
            icon: const Icon(Icons.contacts),
            onPressed: () => _abrir(const ContactosScreen()),
          ),
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings),
            onPressed: () => _abrir(const AjustesScreen()),
          ),
        ],
      ),
      body: SafeArea(
        child: !p.cargado
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, c) {
                  final tamano = math.min(c.maxWidth * 0.62, c.maxHeight * 0.36).clamp(160.0, 280.0);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: math.max(0.0, c.maxHeight - 28)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (avisoAutomatico != null)
                            Card(
                              color: Colors.orange.shade50,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.alarm, color: Colors.deepOrange),
                                title: Text(avisoAutomatico),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: prot.limpiarAvisoAutomatico,
                                ),
                              ),
                            ),
                          if (prot.seguimientoActivo)
                            Card(
                              color: Colors.blue.shade50,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.share_location, color: Colors.blue),
                                title: const Text('Ubicación en vivo activa'),
                                subtitle: Text(prot.resultadoSeguimiento ??
                                    'Se envía por SMS cada ${p.ajustes.intervaloSeguimientoMin} min.'),
                                trailing: TextButton(
                                  onPressed: prot.detenerSeguimiento,
                                  child: const Text('Detener'),
                                ),
                              ),
                            ),
                          if (prot.sirenaActiva || prot.linternaActiva)
                            Card(
                              color: Colors.red.shade50,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.campaign, color: Colors.red),
                                title: Text(
                                  prot.sirenaActiva && prot.linternaActiva
                                      ? 'Sirena y linterna encendidas'
                                      : (prot.sirenaActiva ? 'Sirena encendida' : 'Linterna S.O.S. encendida'),
                                ),
                                trailing: TextButton(
                                  onPressed: () {
                                    prot.ponerSirena(false);
                                    prot.ponerLinterna(false);
                                  },
                                  child: const Text('Apagar'),
                                ),
                              ),
                            ),
                          _Estado(provider: p, onContactos: () => _abrir(const ContactosScreen())),
                          const SizedBox(height: 8),
                          BotonSos(
                            tamano: tamano.toDouble(),
                            ocupado: _ocupado,
                            onPressed: () => _iniciar(TipoAlerta.emergencia),
                          ),
                          Text(
                            p.ajustes.segundosCuentaRegresiva > 0
                                ? 'Toca el botón. Tendrás ${p.ajustes.segundosCuentaRegresiva} s para cancelar.'
                                : 'Toca el botón para enviar la alerta de inmediato.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _Accion(
                                  icono: Icons.science_outlined,
                                  texto: 'Prueba',
                                  color: Colors.blue,
                                  onTap: () => _iniciar(TipoAlerta.prueba),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _Accion(
                                  icono: Icons.verified_user_outlined,
                                  texto: 'Estoy a salvo',
                                  color: Colors.green,
                                  onTap: () => _iniciar(TipoAlerta.aSalvo),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _Accion(
                                  icono: Icons.local_phone,
                                  texto: linea.isEmpty ? 'Llamar' : 'Llamar $linea',
                                  color: Colors.red.shade700,
                                  onTap: linea.isEmpty
                                      ? null
                                      : () => Nativo.llamar(linea, directo: p.ajustes.llamadaDirecta),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const TarjetaLlegueBien(),
                          const SizedBox(height: 10),
                          Text(
                            'AlertaYa no reemplaza a la línea de emergencias'
                            '${linea.isEmpty ? '' : ' $linea'}. Ante un peligro inmediato, llama.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _Estado extends StatelessWidget {
  const _Estado({required this.provider, required this.onContactos});

  final EmergenciaProvider provider;
  final VoidCallback onContactos;

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final n = p.contactos.length;

    String gpsTexto = '';
    bool gpsOk = false;
    VoidCallback? gpsAccion;
    switch (p.estadoGps) {
      case EstadoGps.listo:
        gpsTexto = 'GPS listo';
        gpsOk = true;
      case EstadoGps.gpsApagado:
        gpsTexto = 'GPS apagado · toca para activar';
        gpsAccion = () => p.ubicacion.abrirAjustesGps();
      case EstadoGps.sinPermiso:
        gpsTexto = 'Sin permiso de ubicación · toca para permitir';
        gpsAccion = () => p.actualizarEstados(pedirPermisoGps: true);
      case EstadoGps.permisoBloqueado:
        gpsTexto = 'Ubicación bloqueada · toca para abrir ajustes';
        gpsAccion = () => p.ubicacion.abrirAjustesApp();
      case EstadoGps.desconocido:
        gpsTexto = 'Comprobando GPS…';
        gpsAccion = () => p.actualizarEstados(pedirPermisoGps: true);
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            _Fila(
              ok: n > 0,
              icono: Icons.people,
              texto: n == 0
                  ? 'No tienes contactos · toca para agregar'
                  : '$n contacto${n == 1 ? '' : 's'} de emergencia guardado${n == 1 ? '' : 's'}',
              onTap: onContactos,
            ),
            _Fila(ok: gpsOk, icono: Icons.location_on, texto: gpsTexto, onTap: gpsAccion),
            if (Nativo.esAndroid && p.ajustes.smsAutomatico)
              _Fila(
                ok: p.permisoSms,
                icono: Icons.sms,
                texto: p.permisoSms
                    ? 'SMS automático activo'
                    : 'Permite enviar SMS automáticos · toca aquí',
                onTap: p.permisoSms ? null : () => p.pedirPermisoSms(),
              ),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.ok, required this.icono, required this.texto, this.onTap});

  final bool ok;
  final IconData icono;
  final String texto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.green.shade700 : Colors.orange.shade800;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icono, color: color),
      title: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      trailing: Icon(ok ? Icons.check_circle : Icons.error_outline, color: color, size: 20),
      onTap: onTap,
    );
  }
}

class _Accion extends StatelessWidget {
  const _Accion({required this.icono, required this.texto, required this.color, this.onTap});

  final IconData icono;
  final String texto;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(120)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono),
          const SizedBox(height: 4),
          Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
