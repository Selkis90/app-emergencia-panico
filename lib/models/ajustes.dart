import 'dart:convert';

/// Preferencias del usuario. Se guardan en el teléfono y no se pierden
/// al cerrar la app.
class Ajustes {
  /// Nombre que aparece en el mensaje ("Ana necesita ayuda").
  final String nombreUsuario;

  /// Código de país que se antepone a los números sin indicativo (57 = Colombia).
  final String codigoPais;

  /// Texto libre que se agrega al mensaje de emergencia.
  final String mensajePersonalizado;

  /// Datos útiles para quien ayuda: tipo de sangre, alergias, EPS, etc.
  final String infoAdicional;

  /// Línea de emergencias local (123 en Colombia).
  final String numeroEmergencias;

  /// Segundos de cuenta regresiva antes de enviar (0 = enviar de inmediato).
  final int segundosCuentaRegresiva;

  /// Enviar los SMS automáticamente, sin abrir la app de mensajes.
  final bool smsAutomatico;

  /// Mostrar el envío por WhatsApp después del SMS.
  final bool usarWhatsApp;

  /// Abrir automáticamente el siguiente chat de WhatsApp al volver a la app.
  final bool whatsappContinuo;

  /// Vibrar en código Morse S.O.S. al enviar la alerta.
  final bool vibracionSos;

  /// Llamar directamente (sin pasar por el marcador) al contacto principal.
  final bool llamadaDirecta;

  const Ajustes({
    this.nombreUsuario = '',
    this.codigoPais = '57',
    this.mensajePersonalizado = '',
    this.infoAdicional = '',
    this.numeroEmergencias = '123',
    this.segundosCuentaRegresiva = 5,
    this.smsAutomatico = true,
    this.usarWhatsApp = true,
    this.whatsappContinuo = true,
    this.vibracionSos = true,
    this.llamadaDirecta = false,
  });

  Ajustes copyWith({
    String? nombreUsuario,
    String? codigoPais,
    String? mensajePersonalizado,
    String? infoAdicional,
    String? numeroEmergencias,
    int? segundosCuentaRegresiva,
    bool? smsAutomatico,
    bool? usarWhatsApp,
    bool? whatsappContinuo,
    bool? vibracionSos,
    bool? llamadaDirecta,
  }) {
    return Ajustes(
      nombreUsuario: nombreUsuario ?? this.nombreUsuario,
      codigoPais: codigoPais ?? this.codigoPais,
      mensajePersonalizado: mensajePersonalizado ?? this.mensajePersonalizado,
      infoAdicional: infoAdicional ?? this.infoAdicional,
      numeroEmergencias: numeroEmergencias ?? this.numeroEmergencias,
      segundosCuentaRegresiva:
          segundosCuentaRegresiva ?? this.segundosCuentaRegresiva,
      smsAutomatico: smsAutomatico ?? this.smsAutomatico,
      usarWhatsApp: usarWhatsApp ?? this.usarWhatsApp,
      whatsappContinuo: whatsappContinuo ?? this.whatsappContinuo,
      vibracionSos: vibracionSos ?? this.vibracionSos,
      llamadaDirecta: llamadaDirecta ?? this.llamadaDirecta,
    );
  }

  Map<String, dynamic> toJson() => {
        'nombreUsuario': nombreUsuario,
        'codigoPais': codigoPais,
        'mensajePersonalizado': mensajePersonalizado,
        'infoAdicional': infoAdicional,
        'numeroEmergencias': numeroEmergencias,
        'segundosCuentaRegresiva': segundosCuentaRegresiva,
        'smsAutomatico': smsAutomatico,
        'usarWhatsApp': usarWhatsApp,
        'whatsappContinuo': whatsappContinuo,
        'vibracionSos': vibracionSos,
        'llamadaDirecta': llamadaDirecta,
      };

  factory Ajustes.fromJson(Map<String, dynamic> j) {
    const d = Ajustes();
    String s(String k, String def) => j[k] is String ? j[k] as String : def;
    bool b(String k, bool def) => j[k] is bool ? j[k] as bool : def;
    final seg = j['segundosCuentaRegresiva'];
    return Ajustes(
      nombreUsuario: s('nombreUsuario', d.nombreUsuario),
      codigoPais: s('codigoPais', d.codigoPais),
      mensajePersonalizado: s('mensajePersonalizado', d.mensajePersonalizado),
      infoAdicional: s('infoAdicional', d.infoAdicional),
      numeroEmergencias: s('numeroEmergencias', d.numeroEmergencias),
      segundosCuentaRegresiva:
          seg is int ? seg.clamp(0, 30).toInt() : d.segundosCuentaRegresiva,
      smsAutomatico: b('smsAutomatico', d.smsAutomatico),
      usarWhatsApp: b('usarWhatsApp', d.usarWhatsApp),
      whatsappContinuo: b('whatsappContinuo', d.whatsappContinuo),
      vibracionSos: b('vibracionSos', d.vibracionSos),
      llamadaDirecta: b('llamadaDirecta', d.llamadaDirecta),
    );
  }

  String codificar() => jsonEncode(toJson());

  static Ajustes decodificar(String? texto) {
    if (texto == null || texto.isEmpty) return const Ajustes();
    try {
      final j = jsonDecode(texto);
      if (j is Map) return Ajustes.fromJson(Map<String, dynamic>.from(j));
    } catch (_) {}
    return const Ajustes();
  }
}
