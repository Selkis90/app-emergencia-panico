import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/contacto.dart';
import '../providers/emergencia_provider.dart';
import '../services/nativo.dart';
import '../services/ubicacion.dart';
import '../utils/mensajes.dart';

enum _EstadoSms { pendiente, enviando, enviado, sinPermiso, noDisponible, desactivado, sinContactos }

/// Pantalla que ejecuta el envío de la alerta:
/// 1. Obtiene la ubicación (sin bloquear si no hay GPS).
/// 2. Envía SMS automáticos a todos los contactos.
/// 3. Abre WhatsApp contacto por contacto (modo continuo) o en un grupo.
/// 4. Ofrece llamar al contacto principal y a la línea de emergencias.
class EnvioScreen extends StatefulWidget {
  const EnvioScreen({super.key, required this.tipo});

  final TipoAlerta tipo;

  @override
  State<EnvioScreen> createState() => _EnvioScreenState();
}

class _EnvioScreenState extends State<EnvioScreen> with WidgetsBindingObserver {
  bool _buscandoUbicacion = true;
  ResultadoUbicacion? _ubicacion;
  MensajeAlerta? _mensaje;

  _EstadoSms _estadoSms = _EstadoSms.pendiente;
  ResultadoSms? _resultadoSms;

  final Set<String> _whatsappAbiertos = {};
  String? _whatsappActual;
  bool _esperandoRegreso = false;
  bool _continuo = true;
  String? _paqueteWhatsApp;
  Timer? _temporizador;

  EmergenciaProvider get _p => context.read<EmergenciaProvider>();

  bool get _esEmergencia => widget.tipo == TipoAlerta.emergencia;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _continuo = context.read<EmergenciaProvider>().ajustes.whatsappContinuo;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ejecutar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _temporizador?.cancel();
    Nativo.detenerVibracion();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // FLUJO PRINCIPAL
  // ------------------------------------------------------------------

  Future<void> _ejecutar() async {
    final p = _p;
    if (_esEmergencia && p.ajustes.vibracionSos) {
      Nativo.vibrarSos(repeticiones: 2);
    }

    final instalado = await Nativo.whatsappInstalado();
    _paqueteWhatsApp = instalado['normal'] == true
        ? 'com.whatsapp'
        : (instalado['business'] == true ? 'com.whatsapp.w4b' : null);

    await _obtenerUbicacion();
    if (!mounted) return;

    await _enviarSmsAutomatico();
    if (!mounted) return;

    if (p.ajustes.usarWhatsApp && _continuo && p.contactosWhatsApp.isNotEmpty) {
      _temporizador = Timer(const Duration(milliseconds: 900), _abrirSiguienteWhatsApp);
    }
  }

  Future<void> _obtenerUbicacion() async {
    setState(() => _buscandoUbicacion = true);
    final r = await _p.ubicacion.obtener();
    if (!mounted) return;
    setState(() {
      _ubicacion = r;
      _buscandoUbicacion = false;
      _mensaje = _p.construirMensaje(widget.tipo, r.datos);
    });
  }

  Future<void> _enviarSmsAutomatico({bool forzar = false}) async {
    final p = _p;
    final contactos = p.contactosSms;
    if (contactos.isEmpty) {
      setState(() => _estadoSms = _EstadoSms.sinContactos);
      return;
    }
    if (!p.ajustes.smsAutomatico && !forzar) {
      setState(() => _estadoSms = _EstadoSms.desactivado);
      return;
    }
    if (!Nativo.esAndroid) {
      setState(() => _estadoSms = _EstadoSms.noDisponible);
      return;
    }

    var permiso = await Nativo.tienePermiso('sms');
    if (!permiso) permiso = await p.pedirPermisoSms();
    if (!mounted) return;
    if (!permiso) {
      setState(() => _estadoSms = _EstadoSms.sinPermiso);
      return;
    }

    setState(() => _estadoSms = _EstadoSms.enviando);
    final numeros = contactos.map(p.numeroSms).where((n) => n.isNotEmpty).toList();
    final r = await Nativo.enviarSms(numeros, _mensaje!.sms);
    if (!mounted) return;
    setState(() {
      _resultadoSms = r;
      _estadoSms = r.noDisponible ? _EstadoSms.noDisponible : _EstadoSms.enviado;
    });
  }

  Future<void> _abrirAppSms() async {
    final p = _p;
    final numeros = p.contactosSms.map(p.numeroSms).where((n) => n.isNotEmpty).toList();
    final ok = await Nativo.abrirSms(numeros, _mensaje!.sms);
    if (!ok && mounted) _aviso('No se pudo abrir la app de mensajes');
  }

  // ------------------------------------------------------------------
  // WHATSAPP
  // ------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_esperandoRegreso) return;
    // El usuario volvió de WhatsApp: abrimos el siguiente chat.
    _esperandoRegreso = false;
    if (_continuo) {
      _temporizador?.cancel();
      _temporizador = Timer(const Duration(milliseconds: 700), _abrirSiguienteWhatsApp);
    }
  }

  Contacto? get _siguientePendiente {
    for (final c in _p.contactosWhatsApp) {
      if (!_whatsappAbiertos.contains(c.id)) return c;
    }
    return null;
  }

  void _abrirSiguienteWhatsApp() {
    if (!mounted) return;
    final c = _siguientePendiente;
    if (c == null) {
      setState(() => _whatsappActual = null);
      return;
    }
    _abrirWhatsApp(c);
  }

  Future<void> _abrirWhatsApp(Contacto c) async {
    final msg = _mensaje;
    if (msg == null) return;
    final numero = _p.numeroWhatsApp(c);
    setState(() {
      _whatsappActual = c.id;
      _whatsappAbiertos.add(c.id);
    });
    _esperandoRegreso = true;
    final ok = await Nativo.abrirChatWhatsApp(numero, msg.whatsapp, paquete: _paqueteWhatsApp);
    if (!ok) {
      _esperandoRegreso = false;
      if (!mounted) return;
      setState(() => _whatsappAbiertos.remove(c.id));
      _aviso('No se pudo abrir WhatsApp para ${c.nombre}');
    }
  }

  Future<void> _compartirEnGrupo() async {
    final msg = _mensaje;
    if (msg == null) return;
    setState(() => _continuo = false);
    final ok = await Nativo.compartirWhatsApp(msg.whatsapp, paquete: _paqueteWhatsApp);
    if (!ok && mounted) _aviso('No se pudo abrir WhatsApp');
  }

  // ------------------------------------------------------------------

  void _aviso(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _reintentarUbicacion() async {
    await _obtenerUbicacion();
    if (!mounted || _ubicacion?.datos == null) return;
    _aviso('📍 Ubicación actualizada. Reenvía para que la reciban.');
  }

  void _estoyASalvo() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const EnvioScreen(tipo: TipoAlerta.aSalvo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EmergenciaProvider>();
    String titulo;
    Color color;
    switch (widget.tipo) {
      case TipoAlerta.emergencia:
        titulo = '🆘 Alerta S.O.S.';
        color = const Color(0xFFB71C1C);
      case TipoAlerta.prueba:
        titulo = '🧪 Mensaje de prueba';
        color = Colors.blue.shade700;
      case TipoAlerta.aSalvo:
        titulo = '✅ Estoy a salvo';
        color = Colors.green.shade700;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(titulo),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: _mensaje == null
          ? _Cargando(color: color)
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                _tarjetaUbicacion(),
                _tarjetaSms(p),
                if (p.ajustes.usarWhatsApp) _tarjetaWhatsApp(p),
                if (_esEmergencia) _tarjetaLlamadas(p),
                _vistaPrevia(),
                const SizedBox(height: 12),
                if (_esEmergencia)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _estoyASalvo,
                    icon: const Icon(Icons.verified_user),
                    label: const Text('Ya estoy a salvo — avisar a todos'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Volver al inicio'),
                ),
              ],
            ),
    );
  }

  Widget _tarjetaUbicacion() {
    final u = _ubicacion?.datos;
    final estado = _ubicacion?.estado;
    return _Seccion(
      icono: Icons.location_on,
      titulo: 'Ubicación',
      child: _buscandoUbicacion
          ? const Row(children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Obteniendo ubicación…'),
            ])
          : u != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.esUltimaConocida
                          ? '⚠️ Se envía la última ubicación conocida'
                          : '✅ Ubicación incluida en el mensaje',
                    ),
                    if (u.precisionMetros != null)
                      Text('Precisión aproximada: ±${u.precisionMetros!.round()} m',
                          style: TextStyle(color: Colors.grey.shade700)),
                    SelectableText(u.enlaceMaps,
                        style: const TextStyle(fontSize: 12, color: Colors.blue)),
                    if (u.esUltimaConocida)
                      TextButton.icon(
                        onPressed: _reintentarUbicacion,
                        icon: const Icon(Icons.my_location),
                        label: const Text('Intentar ubicación actual'),
                      ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      estado == EstadoGps.gpsApagado
                          ? '❌ GPS apagado: el mensaje se envía sin ubicación.'
                          : '❌ No se pudo obtener la ubicación: el mensaje se envía sin ella.',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (estado == EstadoGps.gpsApagado)
                          TextButton(
                            onPressed: () => _p.ubicacion.abrirAjustesGps(),
                            child: const Text('Activar GPS'),
                          ),
                        if (estado == EstadoGps.permisoBloqueado)
                          TextButton(
                            onPressed: () => _p.ubicacion.abrirAjustesApp(),
                            child: const Text('Dar permiso'),
                          ),
                        TextButton(
                          onPressed: _reintentarUbicacion,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget _tarjetaSms(EmergenciaProvider p) {
    final r = _resultadoSms;
    Widget estado = const SizedBox.shrink();
    switch (_estadoSms) {
      case _EstadoSms.pendiente:
      case _EstadoSms.enviando:
        estado = const Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Enviando SMS…'),
        ]);
      case _EstadoSms.enviado:
        final ok = r?.enviados.length ?? 0;
        final fallos = r?.fallidos ?? const <String, String>{};
        estado = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ok > 0
                  ? '✅ SMS enviado automáticamente a $ok contacto${ok == 1 ? '' : 's'}'
                  : '❌ No se pudo enviar ningún SMS',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final f in fallos.entries)
              Text('• ${f.key}: ${f.value}', style: TextStyle(color: Colors.red.shade700)),
            if (ok > 0)
              Text('Requiere saldo o plan de SMS en tu línea.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        );
      case _EstadoSms.sinPermiso:
        estado = const Text('⚠️ Sin permiso para enviar SMS automáticos. Usa el botón de abajo.');
      case _EstadoSms.noDisponible:
        estado = const Text('El envío automático no está disponible en este equipo.');
      case _EstadoSms.desactivado:
        estado = const Text('El SMS automático está desactivado en Ajustes.');
      case _EstadoSms.sinContactos:
        estado = const Text('Ningún contacto tiene activado el SMS.');
    }

    return _Seccion(
      icono: Icons.sms,
      titulo: 'SMS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          estado,
          if (p.contactosSms.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: _abrirAppSms,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir app de SMS'),
                ),
                if (_estadoSms == _EstadoSms.enviado ||
                    _estadoSms == _EstadoSms.desactivado ||
                    _estadoSms == _EstadoSms.sinPermiso)
                  OutlinedButton.icon(
                    onPressed: () => _enviarSmsAutomatico(forzar: true),
                    icon: const Icon(Icons.send, size: 18),
                    label: Text(_estadoSms == _EstadoSms.enviado ? 'Reenviar' : 'Enviar automático'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaWhatsApp(EmergenciaProvider p) {
    final lista = p.contactosWhatsApp;
    final abiertos = lista.where((c) => _whatsappAbiertos.contains(c.id)).length;
    return _Seccion(
      icono: Icons.chat,
      titulo: 'WhatsApp',
      trailing: lista.isEmpty ? null : Text('$abiertos/${lista.length}'),
      child: lista.isEmpty
          ? const Text('Ningún contacto tiene activado WhatsApp.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_paqueteWhatsApp == null && Nativo.esAndroid)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('⚠️ WhatsApp no parece estar instalado.'),
                  ),
                Text(
                  'WhatsApp no permite enviar mensajes solos: se abre cada chat con '
                  'el mensaje escrito, solo toca ➤ Enviar y vuelve a esta app.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Abrir el siguiente chat al volver'),
                  value: _continuo,
                  onChanged: (v) => setState(() => _continuo = v),
                ),
                for (final c in lista)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      _whatsappAbiertos.contains(c.id)
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: _whatsappAbiertos.contains(c.id) ? Colors.green : Colors.grey,
                    ),
                    title: Text(c.nombre,
                        style: TextStyle(
                          fontWeight: _whatsappActual == c.id ? FontWeight.bold : null,
                        )),
                    subtitle: Text(p.numeroBonito(c)),
                    trailing: FilledButton.tonal(
                      onPressed: () {
                        _temporizador?.cancel();
                        _abrirWhatsApp(c);
                      },
                      child: Text(_whatsappAbiertos.contains(c.id) ? 'Otra vez' : 'Enviar'),
                    ),
                  ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _compartirEnGrupo,
                    icon: const Icon(Icons.groups),
                    label: const Text('Enviar a un grupo o a varios chats'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tarjetaLlamadas(EmergenciaProvider p) {
    final principal = p.contactoPrincipal;
    final linea = p.ajustes.numeroEmergencias.trim();
    final directo = p.ajustes.llamadaDirecta;
    return _Seccion(
      icono: Icons.call,
      titulo: 'Llamar',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (linea.isNotEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB71C1C)),
              onPressed: () async {
                if (directo && !await Nativo.tienePermiso('llamada')) {
                  await Nativo.pedirPermiso('llamada');
                }
                await Nativo.llamar(linea, directo: directo);
              },
              icon: const Icon(Icons.local_phone),
              label: Text('Emergencias $linea'),
            ),
          if (principal != null)
            OutlinedButton.icon(
              onPressed: () async {
                if (directo && !await Nativo.tienePermiso('llamada')) {
                  await Nativo.pedirPermiso('llamada');
                }
                await Nativo.llamar(p.numeroSms(principal), directo: directo);
              },
              icon: const Icon(Icons.person),
              label: Text('Llamar a ${principal.nombre}'),
            ),
        ],
      ),
    );
  }

  Widget _vistaPrevia() {
    final m = _mensaje!;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.visibility),
        title: const Text('Ver el mensaje enviado'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WhatsApp:', style: TextStyle(fontWeight: FontWeight.bold)),
          SelectableText(m.whatsapp),
          const Divider(),
          Text('SMS (${m.sms.length} caracteres):',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          SelectableText(m.sms),
        ],
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.icono, required this.titulo, required this.child, this.trailing});

  final IconData icono;
  final String titulo;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(titulo,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: color),
          const SizedBox(height: 16),
          const Text('Preparando la alerta y obteniendo tu ubicación…'),
        ],
      ),
    );
  }
}
