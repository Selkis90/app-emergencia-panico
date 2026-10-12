import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ajustes.dart';
import '../providers/emergencia_provider.dart';
import '../providers/premium_provider.dart';
import '../services/nativo.dart';
import '../services/ubicacion.dart';
import '../utils/mensajes.dart';
import 'premium_screen.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  late final EmergenciaProvider _p = context.read<EmergenciaProvider>();
  late Ajustes _a = _p.ajustes;

  late final _nombre = TextEditingController(text: _a.nombreUsuario);
  late final _codigo = TextEditingController(text: _a.codigoPais);
  late final _linea = TextEditingController(text: _a.numeroEmergencias);
  late final _mensaje = TextEditingController(text: _a.mensajePersonalizado);
  late final _info = TextEditingController(text: _a.infoAdicional);

  bool _permContactos = false;
  bool _permLlamada = false;

  @override
  void initState() {
    super.initState();
    _revisarPermisos();
  }

  @override
  void dispose() {
    // Guarda lo escrito aunque el usuario salga sin pulsar "Guardar".
    // (En un microtask para no notificar mientras el árbol se desmonta.)
    final datos = _leerFormulario();
    final provider = _p;
    Future.microtask(() => provider.guardarAjustes(datos));
    _nombre.dispose();
    _codigo.dispose();
    _linea.dispose();
    _mensaje.dispose();
    _info.dispose();
    super.dispose();
  }

  Future<void> _revisarPermisos() async {
    final c = await Nativo.tienePermiso('contactos');
    final l = await Nativo.tienePermiso('llamada');
    await _p.actualizarEstados();
    if (!mounted) return;
    setState(() {
      _permContactos = c;
      _permLlamada = l;
    });
  }

  Ajustes _leerFormulario() {
    final codigo = _codigo.text.replaceAll(RegExp(r'\D'), '');
    return _a.copyWith(
      nombreUsuario: _nombre.text.trim(),
      codigoPais: codigo.isEmpty ? '57' : codigo,
      numeroEmergencias: _linea.text.trim(),
      mensajePersonalizado: _mensaje.text.trim(),
      infoAdicional: _info.text.trim(),
    );
  }

  void _cambiar(Ajustes nuevo) {
    setState(() => _a = nuevo);
    _p.guardarAjustes(_leerFormulario());
  }

  Future<void> _guardar() async {
    await _p.guardarAjustes(_leerFormulario());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Ajustes guardados')),
    );
  }

  void _verMensaje() {
    final m = ConstructorMensajes.construir(
      tipo: TipoAlerta.emergencia,
      ajustes: _leerFormulario(),
      ubicacion: const DatosUbicacion(latitud: 4.609710, longitud: -74.081750, precisionMetros: 12),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vista previa'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(m.whatsapp),
              const Divider(),
              Text('SMS (${m.sms.length} caracteres)',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(m.sms),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EmergenciaProvider>();
    final esPremium = context.watch<PremiumProvider>().esPremium;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        actions: [
          IconButton(tooltip: 'Guardar', icon: const Icon(Icons.save), onPressed: _guardar),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Titulo('Tu mensaje'),
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Tu nombre',
              hintText: 'Ej: Andrés',
              helperText: 'Aparece en la alerta: "Andrés necesita ayuda"',
              prefixIcon: Icon(Icons.badge),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mensaje,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Mensaje personalizado (opcional)',
              hintText: 'Estoy en peligro, por favor ayúdame.',
              prefixIcon: Icon(Icons.message),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _info,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Información importante (opcional)',
              hintText: 'Tipo de sangre O+, alérgico a la penicilina, EPS…',
              prefixIcon: Icon(Icons.medical_information),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _verMensaje,
              icon: const Icon(Icons.visibility),
              label: const Text('Ver cómo queda el mensaje'),
            ),
          ),
          const _Titulo('Números'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codigo,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Código de país',
                    prefixText: '+',
                    helperText: '57 = Colombia',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _linea,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Línea de emergencias',
                    helperText: '123 en Colombia',
                  ),
                ),
              ),
            ],
          ),
          const _Titulo('Envío'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cuenta regresiva antes de enviar'),
            subtitle: const Text('Te da tiempo de cancelar si lo tocaste por error'),
            trailing: DropdownButton<int>(
              value: const [0, 3, 5, 10].contains(_a.segundosCuentaRegresiva)
                  ? _a.segundosCuentaRegresiva
                  : 5,
              items: const [
                DropdownMenuItem(value: 0, child: Text('No')),
                DropdownMenuItem(value: 3, child: Text('3 s')),
                DropdownMenuItem(value: 5, child: Text('5 s')),
                DropdownMenuItem(value: 10, child: Text('10 s')),
              ],
              onChanged: (v) => _cambiar(_a.copyWith(segundosCuentaRegresiva: v ?? 5)),
            ),
          ),
          if (Nativo.esAndroid)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('SMS automático'),
              subtitle: const Text('Envía el SMS a todos sin abrir la app de mensajes'),
              value: _a.smsAutomatico,
              onChanged: (v) => _cambiar(_a.copyWith(smsAutomatico: v)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enviar también por WhatsApp'),
            value: _a.usarWhatsApp,
            onChanged: (v) => _cambiar(_a.copyWith(usarWhatsApp: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('WhatsApp continuo'),
            subtitle: const Text('Al volver de WhatsApp se abre el chat del siguiente contacto'),
            value: _a.whatsappContinuo,
            onChanged: _a.usarWhatsApp
                ? (v) => _cambiar(_a.copyWith(whatsappContinuo: v))
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vibración S.O.S.'),
            subtitle: const Text('Vibra en código Morse ··· ——— ··· al enviar'),
            value: _a.vibracionSos,
            onChanged: (v) => _cambiar(_a.copyWith(vibracionSos: v)),
          ),
          if (Nativo.esAndroid)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Llamada directa'),
              subtitle: const Text('Llama sin pasar por el marcador (pide permiso de llamadas)'),
              value: _a.llamadaDirecta,
              onChanged: (v) async {
                if (v && !_permLlamada) {
                  final ok = await Nativo.pedirPermiso('llamada');
                  if (!mounted) return;
                  setState(() => _permLlamada = ok);
                  if (!ok) return;
                }
                _cambiar(_a.copyWith(llamadaDirecta: v));
              },
            ),
          const _Titulo('Premium'),
          if (!esPremium)
            Card(
              color: Colors.amber.shade50,
              child: ListTile(
                leading: Icon(Icons.workspace_premium, color: Colors.amber.shade800),
                title: const Text('Desbloquea AlertaYa Premium'),
                subtitle: const Text('Ubicación en vivo, modo "Llegué bien", sirena y linterna S.O.S.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => abrirPremium(context),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: esPremium,
            title: const Text('Ubicación en vivo: enviar cada'),
            subtitle: const Text('Cada envío es un SMS a cada contacto'),
            trailing: DropdownButton<int>(
              value: const [3, 5, 10, 15].contains(_a.intervaloSeguimientoMin)
                  ? _a.intervaloSeguimientoMin
                  : 5,
              items: const [
                DropdownMenuItem(value: 3, child: Text('3 min')),
                DropdownMenuItem(value: 5, child: Text('5 min')),
                DropdownMenuItem(value: 10, child: Text('10 min')),
                DropdownMenuItem(value: 15, child: Text('15 min')),
              ],
              onChanged: esPremium
                  ? (v) => _cambiar(_a.copyWith(intervaloSeguimientoMin: v ?? 5))
                  : null,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Iniciar ubicación en vivo con cada S.O.S.'),
            value: _a.seguimientoAutomatico,
            onChanged: esPremium ? (v) => _cambiar(_a.copyWith(seguimientoAutomatico: v)) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Encender la sirena con cada S.O.S.'),
            subtitle: const Text('Desactívalo si en un peligro prefieres no hacer ruido'),
            value: _a.sirenaAutomatica,
            onChanged: esPremium ? (v) => _cambiar(_a.copyWith(sirenaAutomatica: v)) : null,
          ),
          TextButton.icon(
            onPressed: () => Nativo.vibrarSos(),
            icon: const Icon(Icons.vibration),
            label: const Text('Probar vibración'),
          ),
          if (Nativo.esAndroid) ...[
            const _Titulo('Permisos'),
            _Permiso(
              titulo: 'Ubicación',
              ok: p.estadoGps == EstadoGps.listo,
              detalle: _textoGps(p.estadoGps),
              onTap: () async {
                if (p.estadoGps == EstadoGps.gpsApagado) {
                  await p.ubicacion.abrirAjustesGps();
                } else if (p.estadoGps == EstadoGps.permisoBloqueado) {
                  await p.ubicacion.abrirAjustesApp();
                } else {
                  await p.actualizarEstados(pedirPermisoGps: true);
                }
              },
            ),
            _Permiso(
              titulo: 'Enviar SMS',
              ok: p.permisoSms,
              detalle: p.permisoSms ? 'Concedido' : 'Necesario para el SMS automático',
              onTap: () => p.pedirPermisoSms(),
            ),
            _Permiso(
              titulo: 'Contactos',
              ok: _permContactos,
              detalle: _permContactos ? 'Concedido' : 'Necesario para buscar en tu agenda',
              onTap: () async {
                final ok = await Nativo.pedirPermiso('contactos');
                if (mounted) setState(() => _permContactos = ok);
              },
            ),
            _Permiso(
              titulo: 'Llamadas',
              ok: _permLlamada,
              detalle: _permLlamada ? 'Concedido' : 'Solo para la llamada directa',
              onTap: () async {
                final ok = await Nativo.pedirPermiso('llamada');
                if (mounted) setState(() => _permLlamada = ok);
              },
            ),
            TextButton.icon(
              onPressed: () => Nativo.abrirAjustesApp(),
              icon: const Icon(Icons.settings_applications),
              label: const Text('Abrir ajustes de la app'),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _guardar,
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

String _textoGps(EstadoGps e) {
  switch (e) {
    case EstadoGps.listo:
      return 'Concedido y GPS encendido';
    case EstadoGps.gpsApagado:
      return 'GPS apagado';
    case EstadoGps.sinPermiso:
      return 'Sin permiso';
    case EstadoGps.permisoBloqueado:
      return 'Bloqueado: actívalo en ajustes';
    case EstadoGps.desconocido:
      return 'Desconocido';
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        texto.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _Permiso extends StatelessWidget {
  const _Permiso({required this.titulo, required this.ok, required this.detalle, this.onTap});

  final String titulo;
  final bool ok;
  final String detalle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok ? Icons.check_circle : Icons.error_outline,
        color: ok ? Colors.green : Colors.orange.shade800,
      ),
      title: Text(titulo),
      subtitle: Text(detalle),
      trailing: ok ? null : const Icon(Icons.chevron_right),
      onTap: ok ? null : onTap,
    );
  }
}
