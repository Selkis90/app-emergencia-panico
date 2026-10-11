import 'package:shared_preferences/shared_preferences.dart';

import '../models/ajustes.dart';
import '../models/contacto.dart';

/// Guarda contactos y ajustes en el teléfono (SharedPreferences).
/// Los datos sobreviven a cerrar la app, reiniciar el teléfono o actualizar
/// la app; solo se pierden si se desinstala o se borran los datos.
class Almacenamiento {
  static const _claveContactos = 'contactos_v2';
  static const _claveAjustes = 'ajustes_v1';

  /// Clave usada por la versión anterior (formato dañado).
  static const _claveAntigua = 'contactosEmergencia';

  Future<List<Contacto>> cargarContactos() async {
    final prefs = await SharedPreferences.getInstance();
    final texto = prefs.getString(_claveContactos);
    if (texto != null) return Contacto.decodificarLista(texto);

    // Migración: recuperar lo que haya guardado la versión anterior.
    final antiguos = _leerListaAntigua(prefs);
    if (antiguos.isNotEmpty) {
      await guardarContactos(antiguos);
      await prefs.remove(_claveAntigua);
    }
    return antiguos;
  }

  List<Contacto> _leerListaAntigua(SharedPreferences prefs) {
    try {
      final lista = prefs.getStringList(_claveAntigua) ?? const <String>[];
      return lista
          .map(Contacto.desdeFormatoAntiguo)
          .whereType<Contacto>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> guardarContactos(List<Contacto> contactos) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(_claveContactos, Contacto.codificarLista(contactos));
  }

  Future<Ajustes> cargarAjustes() async {
    final prefs = await SharedPreferences.getInstance();
    return Ajustes.decodificar(prefs.getString(_claveAjustes));
  }

  Future<bool> guardarAjustes(Ajustes ajustes) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(_claveAjustes, ajustes.codificar());
  }
}
