import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/nativo.dart';
import '../utils/mensajes.dart';
import 'emergencia_provider.dart';

/// Funciones Premium que siguen funcionando después de enviar la alerta:
/// * Ubicación en vivo: reenvía la ubicación por SMS cada pocos minutos.
/// * Temporizador "Llegué bien": si no confirmas a tiempo, envía el S.O.S. solo.
/// * Sirena y linterna S.O.S.
///
/// Importante: funcionan mientras AlertaYa siga abierta o en segundo plano.
/// Si Android cierra la app, el temporizador se revisa apenas se vuelva a abrir.
class ProteccionProvider extends ChangeNotifier with WidgetsBindingObserver {
  ProteccionProvider(this._app) {
    WidgetsBinding.instance.addObserver(this);
    _restaurarTemporizador();
  }

  final EmergenciaProvider _app;

  static const _claveLimite = 'temporizador_limite';
  static const _claveDestino = 'temporizador_destino';

  /// La ubicación en vivo se detiene sola después de este tiempo.
  static const duracionMaximaSeguimiento = Duration(hours: 2);

  // ------------------------------------------------------------------
  // UBICACIÓN EN VIVO
  // ------------------------------------------------------------------

  Timer? _timerSeguimiento;
  DateTime? _seguimientoHasta;
  int _envios = 0;
  DateTime? _ultimoEnvio;
  String? _resultadoSeguimiento;

  bool get seguimientoActivo => _timerSeguimiento != null;
  int get enviosSeguimiento => _envios;
  DateTime? get ultimoEnvio => _ultimoEnvio;
  String? get resultadoSeguimiento => _resultadoSeguimiento;

  void iniciarSeguimiento() {
    _timerSeguimiento?.cancel();
    _envios = 0;
    _ultimoEnvio = null;
    _resultadoSeguimiento = null;
    _seguimientoHasta = DateTime.now().add(duracionMaximaSeguimiento);
    final minutos = _app.ajustes.intervaloSeguimientoMin.clamp(1, 60).toInt();
    _timerSeguimiento = Timer.periodic(
      Duration(minutes: minutos),
      (_) => _enviarActualizacion(),
    );
    notifyListeners();
  }

  void detenerSeguimiento() {
    _timerSeguimiento?.cancel();
    _timerSeguimiento = null;
    _seguimientoHasta = null;
    notifyListeners();
  }

  Future<void> _enviarActualizacion() async {
    final hasta = _seguimientoHasta;
    if (hasta != null && DateTime.now().isAfter(hasta)) {
      detenerSeguimiento();
      return;
    }
    final r = await _app.ubicacion.obtener(limite: const Duration(seconds: 15));
    final u = r.datos;
    if (u == null) {
      _resultadoSeguimiento = 'No se pudo obtener la ubicación en este intento.';
      notifyListeners();
      return;
    }
    _envios++;
    final m = ConstructorMensajes.actualizacion(
      ajustes: _app.ajustes,
      ubicacion: u,
      numero: _envios,
    );
    final res = await Nativo.enviarSms(_numerosSms(), m.sms);
    _ultimoEnvio = DateTime.now();
    _resultadoSeguimiento = res.enviados.isNotEmpty
        ? 'Ubicación #$_envios enviada a ${res.enviados.length} contacto(s).'
        : 'No se pudo enviar el SMS (revisa el permiso de SMS y tu saldo).';
    notifyListeners();
  }

  List<String> _numerosSms() =>
      _app.contactosSms.map(_app.numeroSms).where((n) => n.isNotEmpty).toList();

  // ------------------------------------------------------------------
  // SIRENA Y LINTERNA
  // ------------------------------------------------------------------

  bool _sirena = false;
  bool _linterna = false;

  bool get sirenaActiva => _sirena;
  bool get linternaActiva => _linterna;

  Future<bool> ponerSirena(bool activar) async {
    final ok = await Nativo.sirena(activar);
    if (ok) _sirena = activar;
    notifyListeners();
    return ok;
  }

  Future<bool> ponerLinterna(bool activar) async {
    final ok = await Nativo.linterna(activar);
    if (ok) _linterna = activar;
    notifyListeners();
    return ok;
  }

  /// Se llama al avisar "Estoy a salvo".
  Future<void> apagarTodo() async {
    detenerSeguimiento();
    if (_sirena) await ponerSirena(false);
    if (_linterna) await ponerLinterna(false);
    await Nativo.detenerVibracion();
  }

  // ------------------------------------------------------------------
  // TEMPORIZADOR "LLEGUÉ BIEN"
  // ------------------------------------------------------------------

  DateTime? _limite;
  String _destino = '';
  Timer? _timerLimite;
  bool _enviandoAutomatico = false;
  String? _ultimaAlertaAutomatica;

  bool get temporizadorActivo => _limite != null;
  DateTime? get limite => _limite;
  String get destino => _destino;
  String? get ultimaAlertaAutomatica => _ultimaAlertaAutomatica;

  Duration get restante {
    final l = _limite;
    if (l == null) return Duration.zero;
    final d = l.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Future<void> iniciarTemporizador(Duration duracion, {String destino = ''}) async {
    _limite = DateTime.now().add(duracion);
    _destino = destino.trim();
    _ultimaAlertaAutomatica = null;
    _programar();
    await _guardar();
    notifyListeners();
  }

  Future<void> extenderTemporizador(Duration extra) async {
    final l = _limite;
    if (l == null) return;
    final base = l.isBefore(DateTime.now()) ? DateTime.now() : l;
    _limite = base.add(extra);
    _programar();
    await _guardar();
    notifyListeners();
  }

  /// El usuario confirma que llegó bien: se cancela sin enviar nada.
  Future<void> llegueBien() async {
    await _limpiarTemporizador();
    notifyListeners();
  }

  void limpiarAvisoAutomatico() {
    _ultimaAlertaAutomatica = null;
    notifyListeners();
  }

  void _programar() {
    _timerLimite?.cancel();
    final l = _limite;
    if (l == null) return;
    final espera = l.difference(DateTime.now());
    _timerLimite = Timer(espera.isNegative ? Duration.zero : espera, _vencer);
  }

  Future<void> _vencer() async {
    if (_limite == null || _enviandoAutomatico) return;
    _enviandoAutomatico = true;
    final destino = _destino;
    await _limpiarTemporizador();
    notifyListeners();
    try {
      await Nativo.vibrarSos(repeticiones: 2);
      final r = await _app.ubicacion.obtener();
      final motivo = destino.isEmpty
          ? 'No confirmó que llegó bien a tiempo (alerta automática).'
          : 'No confirmó que llegó bien a "$destino" a tiempo (alerta automática).';
      final m = _app.construirMensaje(TipoAlerta.emergencia, r.datos, motivo: motivo);
      final res = await Nativo.enviarSms(_numerosSms(), m.sms);
      final hora = ConstructorMensajes.fechaHora(DateTime.now());
      _ultimaAlertaAutomatica = res.enviados.isNotEmpty
          ? '⏰ El temporizador venció y se envió la alerta S.O.S. a '
              '${res.enviados.length} contacto(s) ($hora).'
          : '⏰ El temporizador venció pero NO se pudo enviar el SMS ($hora). '
              'Revisa el permiso de SMS y envía la alerta manualmente.';
      if (res.enviados.isNotEmpty && _app.ajustes.seguimientoAutomatico) {
        iniciarSeguimiento();
      }
    } catch (e) {
      _ultimaAlertaAutomatica = '⏰ El temporizador venció. Error al enviar: $e';
    } finally {
      _enviandoAutomatico = false;
      notifyListeners();
    }
  }

  Future<void> _guardar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final l = _limite;
      if (l == null) {
        await prefs.remove(_claveLimite);
        await prefs.remove(_claveDestino);
      } else {
        await prefs.setInt(_claveLimite, l.millisecondsSinceEpoch);
        await prefs.setString(_claveDestino, _destino);
      }
    } catch (_) {}
  }

  Future<void> _limpiarTemporizador() async {
    _timerLimite?.cancel();
    _timerLimite = null;
    _limite = null;
    _destino = '';
    await _guardar();
  }

  /// Si la app se cerró con un temporizador activo, lo recupera al abrir.
  Future<void> _restaurarTemporizador() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_claveLimite);
      if (ms == null) return;
      _limite = DateTime.fromMillisecondsSinceEpoch(ms);
      _destino = prefs.getString(_claveDestino) ?? '';
      // Espera a que se carguen los contactos antes de poder enviar.
      await Future<void>.delayed(const Duration(seconds: 2));
      _programar();
      notifyListeners();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Si Android congeló la app, el Timer pudo no dispararse a tiempo.
    if (state == AppLifecycleState.resumed) {
      final l = _limite;
      if (l != null && DateTime.now().isAfter(l)) _vencer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerSeguimiento?.cancel();
    _timerLimite?.cancel();
    super.dispose();
  }
}
