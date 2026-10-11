import 'dart:convert';

/// Contacto de emergencia guardado dentro de la app.
class Contacto {
  final String id;
  final String nombre;

  /// Número tal como lo escribió el usuario o venía en la agenda.
  final String telefono;

  /// Recibe el SMS automático.
  final bool enviarSms;

  /// Aparece en la lista de envío por WhatsApp.
  final bool enviarWhatsApp;

  /// Contacto principal: es el que se llama con el botón "Llamar".
  final bool principal;

  const Contacto({
    required this.id,
    required this.nombre,
    required this.telefono,
    this.enviarSms = true,
    this.enviarWhatsApp = true,
    this.principal = false,
  });

  String get inicial {
    final n = nombre.trim();
    return n.isEmpty ? '?' : String.fromCharCode(n.runes.first).toUpperCase();
  }

  Contacto copyWith({
    String? nombre,
    String? telefono,
    bool? enviarSms,
    bool? enviarWhatsApp,
    bool? principal,
  }) {
    return Contacto(
      id: id,
      nombre: nombre ?? this.nombre,
      telefono: telefono ?? this.telefono,
      enviarSms: enviarSms ?? this.enviarSms,
      enviarWhatsApp: enviarWhatsApp ?? this.enviarWhatsApp,
      principal: principal ?? this.principal,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'telefono': telefono,
        'enviarSms': enviarSms,
        'enviarWhatsApp': enviarWhatsApp,
        'principal': principal,
      };

  factory Contacto.fromJson(Map<String, dynamic> json) {
    return Contacto(
      id: (json['id'] ?? generarId()).toString(),
      nombre: (json['nombre'] ?? 'Contacto').toString(),
      telefono: (json['telefono'] ?? '').toString(),
      enviarSms: json['enviarSms'] is bool ? json['enviarSms'] as bool : true,
      enviarWhatsApp:
          json['enviarWhatsApp'] is bool ? json['enviarWhatsApp'] as bool : true,
      principal: json['principal'] is bool ? json['principal'] as bool : false,
    );
  }

  static String codificarLista(List<Contacto> contactos) =>
      jsonEncode(contactos.map((c) => c.toJson()).toList());

  static List<Contacto> decodificarLista(String? texto) {
    if (texto == null || texto.trim().isEmpty) return [];
    try {
      final datos = jsonDecode(texto);
      if (datos is! List) return [];
      return datos
          .whereType<Map>()
          .map((m) => Contacto.fromJson(Map<String, dynamic>.from(m)))
          .where((c) => c.telefono.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// La versión anterior de la app guardaba `Map.toString()` (no era JSON), por
  /// eso los contactos "se borraban". Esto recupera esos datos antiguos:
  /// `{id: 1, nombre: Ana, telefono: 300 123, esEmergencia: true}`
  static Contacto? desdeFormatoAntiguo(String texto) {
    try {
      final json = jsonDecode(texto);
      if (json is Map) return Contacto.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      // No era JSON: probamos con el formato antiguo.
    }
    final m = RegExp(
      r'^\{id: (.*?), nombre: (.*), telefono: (.*?), esEmergencia: (true|false)\}$',
    ).firstMatch(texto.trim());
    if (m == null) return null;
    final telefono = m.group(3)!.trim();
    if (telefono.isEmpty) return null;
    return Contacto(
      id: m.group(1)!.trim(),
      nombre: m.group(2)!.trim(),
      telefono: telefono,
    );
  }

  static int _contador = 0;

  /// Id único aunque se creen varios contactos en el mismo milisegundo
  /// (antes todos quedaban con el mismo id y al borrar uno se borraban todos).
  static String generarId() {
    _contador++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_contador';
  }
}
