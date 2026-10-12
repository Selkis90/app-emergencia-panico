import 'package:flutter/foundation.dart';

import '../models/ajustes.dart';
import '../models/contacto.dart';
import '../services/almacenamiento.dart';
import '../services/nativo.dart';
import '../services/ubicacion.dart';
import '../utils/mensajes.dart';
import '../utils/telefono.dart';

/// Estado global de la app: contactos, ajustes y estado del GPS.
/// No guarda BuildContext (antes sí, y eso causaba errores al mostrar
/// diálogos después de operaciones asíncronas).
class EmergenciaProvider extends ChangeNotifier {
  EmergenciaProvider({Almacenamiento? almacenamiento, ServicioUbicacion? ubicacion})
      : _almacenamiento = almacenamiento ?? Almacenamiento(),
        ubicacion = ubicacion ?? ServicioUbicacion();

  final Almacenamiento _almacenamiento;
  final ServicioUbicacion ubicacion;

  bool _cargado = false;
  List<Contacto> _contactos = [];
  Ajustes _ajustes = const Ajustes();
  EstadoGps _estadoGps = EstadoGps.desconocido;
  bool _permisoSms = false;

  bool get cargado => _cargado;
  List<Contacto> get contactos => List.unmodifiable(_contactos);
  Ajustes get ajustes => _ajustes;
  EstadoGps get estadoGps => _estadoGps;
  bool get permisoSms => _permisoSms;

  List<Contacto> get contactosSms => _contactos.where((c) => c.enviarSms).toList();
  List<Contacto> get contactosWhatsApp =>
      _contactos.where((c) => c.enviarWhatsApp).toList();

  Contacto? get contactoPrincipal {
    for (final c in _contactos) {
      if (c.principal) return c;
    }
    return _contactos.isEmpty ? null : _contactos.first;
  }

  Future<void> cargar() async {
    _contactos = await _almacenamiento.cargarContactos();
    _ajustes = await _almacenamiento.cargarAjustes();
    _cargado = true;
    notifyListeners();
    await actualizarEstados();
  }

  Future<void> actualizarEstados({bool pedirPermisoGps = false}) async {
    _estadoGps = await ubicacion.revisarEstado(pedirPermiso: pedirPermisoGps);
    _permisoSms = await Nativo.tienePermiso('sms');
    notifyListeners();
  }

  Future<bool> pedirPermisoSms() async {
    _permisoSms = await Nativo.pedirPermiso('sms');
    notifyListeners();
    return _permisoSms;
  }

  // ------------------------------------------------------------------
  // CONTACTOS
  // ------------------------------------------------------------------

  bool yaGuardado(String telefono) {
    final k = Telefono.clave(telefono);
    return _contactos.any((c) => Telefono.clave(c.telefono) == k);
  }

  /// Agrega contactos evitando duplicados. Devuelve cuántos se agregaron.
  Future<int> agregarContactos(List<Contacto> nuevos) async {
    var agregados = 0;
    for (final c in nuevos) {
      if (!Telefono.esValido(c.telefono) || yaGuardado(c.telefono)) continue;
      _contactos.add(c);
      agregados++;
    }
    if (agregados > 0) await _guardarContactos();
    return agregados;
  }

  Future<bool> agregarManual(String nombre, String telefono) async {
    final n = await agregarContactos([
      Contacto(
        id: Contacto.generarId(),
        nombre: nombre.trim().isEmpty ? 'Contacto' : nombre.trim(),
        telefono: telefono.trim(),
      ),
    ]);
    return n > 0;
  }

  Future<void> actualizarContacto(Contacto actualizado) async {
    final i = _contactos.indexWhere((c) => c.id == actualizado.id);
    if (i < 0) return;
    _contactos[i] = actualizado;
    await _guardarContactos();
  }

  Future<void> marcarPrincipal(String id) async {
    _contactos = _contactos
        .map((c) => c.copyWith(principal: c.id == id ? !c.principal : false))
        .toList();
    await _guardarContactos();
  }

  Future<void> eliminarContacto(String id) async {
    _contactos.removeWhere((c) => c.id == id);
    await _guardarContactos();
  }

  /// Para "Deshacer" después de eliminar.
  Future<void> restaurarContacto(Contacto c, int posicion) async {
    if (_contactos.any((x) => x.id == c.id)) return;
    _contactos.insert(posicion.clamp(0, _contactos.length).toInt(), c);
    await _guardarContactos();
  }

  Future<void> _guardarContactos() async {
    notifyListeners();
    await _almacenamiento.guardarContactos(_contactos);
  }

  // ------------------------------------------------------------------
  // AJUSTES
  // ------------------------------------------------------------------

  Future<void> guardarAjustes(Ajustes nuevos) async {
    _ajustes = nuevos;
    notifyListeners();
    await _almacenamiento.guardarAjustes(nuevos);
  }

  // ------------------------------------------------------------------
  // MENSAJES
  // ------------------------------------------------------------------

  MensajeAlerta construirMensaje(TipoAlerta tipo, DatosUbicacion? u, {String? motivo}) =>
      ConstructorMensajes.construir(
        tipo: tipo,
        ajustes: _ajustes,
        ubicacion: u,
        motivo: motivo,
      );

  String numeroWhatsApp(Contacto c) => Telefono.internacional(c.telefono, _ajustes.codigoPais);

  String numeroSms(Contacto c) => Telefono.e164(c.telefono, _ajustes.codigoPais);

  String numeroBonito(Contacto c) => Telefono.bonito(c.telefono, _ajustes.codigoPais);
}
