import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Contacto leído de la agenda del teléfono.
class ContactoAgenda {
  final String id;
  final String nombre;
  final String telefono;

  /// "Móvil", "Casa", "Trabajo"...
  final String tipo;

  const ContactoAgenda({
    required this.id,
    required this.nombre,
    required this.telefono,
    this.tipo = '',
  });
}

class ResultadoSms {
  final List<String> enviados;
  final Map<String, String> fallidos;

  /// true si en esta plataforma no existe el envío automático.
  final bool noDisponible;

  const ResultadoSms({
    this.enviados = const [],
    this.fallidos = const {},
    this.noDisponible = false,
  });
}

/// Puente con el código nativo de Android (MainActivity.kt).
/// En otras plataformas usa url_launcher como respaldo.
class Nativo {
  Nativo._();

  static const _canal = MethodChannel('emergencia/nativo');

  static bool get esAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<T?> _invocar<T>(String metodo, [Map<String, dynamic>? args]) async {
    if (!esAndroid) return null;
    try {
      return await _canal.invokeMethod<T>(metodo, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('Nativo.$metodo: ${e.code} ${e.message}');
      return null;
    }
  }

  // ---------------- Permisos ----------------

  /// permiso: 'contactos' | 'sms' | 'llamada'
  static Future<bool> tienePermiso(String permiso) async =>
      (await _invocar<bool>('tienePermiso', {'permiso': permiso})) ?? false;

  static Future<bool> pedirPermiso(String permiso) async =>
      (await _invocar<bool>('pedirPermiso', {'permiso': permiso})) ?? false;

  static Future<bool> abrirAjustesApp() async =>
      (await _invocar<bool>('abrirAjustesApp')) ?? false;

  // ---------------- Agenda ----------------

  static Future<List<ContactoAgenda>> obtenerContactos() async {
    final datos = await _invocar<List<dynamic>>('obtenerContactos');
    if (datos == null) return [];
    final vistos = <String>{};
    final lista = <ContactoAgenda>[];
    for (final d in datos) {
      if (d is! Map) continue;
      final id = (d['id'] ?? '').toString();
      final nombre = (d['nombre'] ?? '').toString().trim();
      final telefono = (d['telefono'] ?? '').toString().trim();
      final digitos = telefono.replaceAll(RegExp(r'\D'), '');
      if (digitos.isEmpty) continue;
      // La agenda suele repetir el mismo número (WhatsApp, Google, SIM...).
      final clave =
          '$id|${digitos.length > 10 ? digitos.substring(digitos.length - 10) : digitos}';
      if (!vistos.add(clave)) continue;
      lista.add(ContactoAgenda(
        id: id,
        nombre: nombre.isEmpty ? telefono : nombre,
        telefono: telefono,
        tipo: (d['tipo'] ?? '').toString(),
      ));
    }
    return lista;
  }

  // ---------------- SMS ----------------

  /// Envía el SMS en segundo plano a todos los números (solo Android).
  static Future<ResultadoSms> enviarSms(List<String> numeros, String mensaje) async {
    if (!esAndroid) return const ResultadoSms(noDisponible: true);
    final r = await _invocar<Map<dynamic, dynamic>>(
      'enviarSms',
      {'numeros': numeros, 'mensaje': mensaje},
    );
    if (r == null) return const ResultadoSms(noDisponible: true);
    final enviados = (r['enviados'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final fallidos = <String, String>{};
    for (final f in (r['fallidos'] as List?) ?? const []) {
      if (f is Map) {
        fallidos[(f['numero'] ?? '').toString()] = (f['error'] ?? '').toString();
      }
    }
    return ResultadoSms(enviados: enviados, fallidos: fallidos);
  }

  /// Abre la app de mensajes con todos los destinatarios y el texto escrito.
  static Future<bool> abrirSms(List<String> numeros, String mensaje) async {
    final ok = await _invocar<bool>('abrirSms', {'numeros': numeros, 'mensaje': mensaje});
    if (ok != null) return ok;
    final uri = Uri.parse(
      'sms:${numeros.join(',')}?body=${Uri.encodeComponent(mensaje)}',
    );
    return _lanzar(uri);
  }

  // ---------------- WhatsApp ----------------

  /// {'normal': bool, 'business': bool}
  static Future<Map<String, bool>> whatsappInstalado() async {
    final r = await _invocar<Map<dynamic, dynamic>>('whatsappInstalado');
    if (r == null) return const {'normal': true, 'business': false};
    return {
      'normal': r['normal'] == true,
      'business': r['business'] == true,
    };
  }

  /// [telefono] en formato internacional solo dígitos (573001234567).
  static Future<bool> abrirChatWhatsApp(
    String telefono,
    String mensaje, {
    String? paquete,
  }) async {
    final ok = await _invocar<bool>('abrirChatWhatsApp', {
      'telefono': telefono,
      'mensaje': mensaje,
      'paquete': paquete,
    });
    if (ok == true) return true;
    final uri = Uri.parse('https://wa.me/$telefono?text=${Uri.encodeComponent(mensaje)}');
    return _lanzar(uri);
  }

  /// Abre WhatsApp para elegir chats o un GRUPO y enviar el mensaje.
  static Future<bool> compartirWhatsApp(String mensaje, {String? paquete}) async {
    final ok = await _invocar<bool>('compartirWhatsApp', {
      'mensaje': mensaje,
      'paquete': paquete,
    });
    if (ok == true) return true;
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(mensaje)}');
    return _lanzar(uri);
  }

  // ---------------- Llamadas ----------------

  static Future<bool> llamar(String numero, {bool directo = false}) async {
    final ok = await _invocar<bool>('llamar', {'numero': numero, 'directo': directo});
    if (ok == true) return true;
    return _lanzar(Uri(scheme: 'tel', path: numero));
  }

  // ---------------- Vibración ----------------

  static Future<void> vibrarSos({int repeticiones = 1}) async {
    final ok = await _invocar<bool>('vibrarSos', {'repeticiones': repeticiones});
    if (ok == null) await HapticFeedback.heavyImpact();
  }

  static Future<void> detenerVibracion() async {
    await _invocar<bool>('detenerVibracion');
  }

  // ---------------- Respaldo ----------------

  static Future<bool> _lanzar(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('No se pudo abrir $uri: $e');
      return false;
    }
  }
}
