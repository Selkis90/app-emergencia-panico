import '../models/ajustes.dart';

enum TipoAlerta { emergencia, prueba, aSalvo }

/// Datos de ubicación que van en el mensaje (independiente del plugin GPS).
class DatosUbicacion {
  final double latitud;
  final double longitud;
  final double? precisionMetros;
  final DateTime? fecha;

  /// true si no se logró una posición nueva y se usa la última conocida.
  final bool esUltimaConocida;

  const DatosUbicacion({
    required this.latitud,
    required this.longitud,
    this.precisionMetros,
    this.fecha,
    this.esUltimaConocida = false,
  });

  String get enlaceMaps =>
      'https://maps.google.com/?q=${latitud.toStringAsFixed(6)},${longitud.toStringAsFixed(6)}';
}

/// Mensaje listo en dos versiones.
class MensajeAlerta {
  /// Versión con emojis y *negritas* para WhatsApp.
  final String whatsapp;

  /// Versión corta, sin emojis ni tildes, para que el SMS ocupe menos
  /// partes (los emojis convierten el SMS a 70 caracteres por parte).
  final String sms;

  const MensajeAlerta({required this.whatsapp, required this.sms});
}

class ConstructorMensajes {
  ConstructorMensajes._();

  static String _dosDigitos(int n) => n.toString().padLeft(2, '0');

  static String fechaHora(DateTime f) =>
      '${_dosDigitos(f.day)}/${_dosDigitos(f.month)}/${f.year} '
      '${_dosDigitos(f.hour)}:${_dosDigitos(f.minute)}';

  static String _hace(DateTime f, DateTime ahora) {
    final min = ahora.difference(f).inMinutes;
    if (min < 1) return 'hace menos de 1 min';
    if (min < 60) return 'hace $min min';
    final h = min ~/ 60;
    return 'hace $h h';
  }

  static MensajeAlerta construir({
    required TipoAlerta tipo,
    required Ajustes ajustes,
    DatosUbicacion? ubicacion,
    DateTime? ahora,
  }) {
    final fecha = ahora ?? DateTime.now();
    final nombre =
        ajustes.nombreUsuario.trim().isEmpty ? 'Tu contacto' : ajustes.nombreUsuario.trim();
    final linea = ajustes.numeroEmergencias.trim();

    switch (tipo) {
      case TipoAlerta.emergencia:
        return _emergencia(nombre, linea, ajustes, ubicacion, fecha);
      case TipoAlerta.prueba:
        return _prueba(nombre, ubicacion, fecha);
      case TipoAlerta.aSalvo:
        return _aSalvo(nombre, ubicacion, fecha);
    }
  }

  static MensajeAlerta _emergencia(
    String nombre,
    String linea,
    Ajustes ajustes,
    DatosUbicacion? u,
    DateTime fecha,
  ) {
    final personal = ajustes.mensajePersonalizado.trim().isEmpty
        ? 'Estoy en peligro, por favor ayúdame.'
        : ajustes.mensajePersonalizado.trim();
    final info = ajustes.infoAdicional.trim();

    final w = StringBuffer()
      ..writeln('🆘🆘🆘 *S.O.S. — EMERGENCIA* 🆘🆘🆘')
      ..writeln()
      ..writeln('*$nombre necesita ayuda URGENTE.*')
      ..writeln('💬 $personal')
      ..writeln();
    if (u != null) {
      w.writeln('📍 *Ubicación:* ${u.enlaceMaps}');
      if (u.precisionMetros != null) {
        w.writeln('🎯 Precisión: ±${u.precisionMetros!.round()} m');
      }
      if (u.esUltimaConocida && u.fecha != null) {
        w.writeln('⚠️ Última ubicación conocida (${_hace(u.fecha!, fecha)})');
      }
    } else {
      w.writeln('📍 Ubicación: no disponible (GPS apagado o sin señal)');
    }
    w.writeln('🕒 ${fechaHora(fecha)}');
    if (info.isNotEmpty) {
      w
        ..writeln()
        ..writeln('🩺 *Información importante:* $info');
    }
    w.writeln();
    if (linea.isNotEmpty) {
      w.writeln('☎️ Si no respondo, llama a la línea de emergencias *$linea*.');
    }
    w.write('_Enviado con mi botón de pánico_');

    final s = StringBuffer('SOS EMERGENCIA! $nombre necesita ayuda URGENTE. $personal');
    if (u != null) {
      s.write(' Ubicacion: ${u.enlaceMaps}');
      if (u.precisionMetros != null) s.write(' (+-${u.precisionMetros!.round()}m)');
      if (u.esUltimaConocida) s.write(' ultima conocida');
    } else {
      s.write(' Ubicacion no disponible.');
    }
    s.write(' ${fechaHora(fecha)}.');
    if (info.isNotEmpty) s.write(' Info: $info.');
    if (linea.isNotEmpty) s.write(' Si no respondo llama al $linea.');

    return MensajeAlerta(whatsapp: w.toString(), sms: textoSms(s.toString()));
  }

  static MensajeAlerta _prueba(String nombre, DatosUbicacion? u, DateTime fecha) {
    final w = StringBuffer()
      ..writeln('🧪 *MENSAJE DE PRUEBA* — no es una emergencia')
      ..writeln()
      ..writeln('$nombre está probando su botón de pánico. ¡Todo está bien! 👍')
      ..writeln('Te tengo como contacto de emergencia: si algún día recibes un *S.O.S.* mío, es real.');
    if (u != null) w.writeln('📍 ${u.enlaceMaps}');
    w.write('🕒 ${fechaHora(fecha)}');

    final s = StringBuffer(
      'PRUEBA (no es emergencia): $nombre esta probando su boton de panico. '
      'Todo bien. Si algun dia recibes un SOS mio, es real.',
    );
    if (u != null) s.write(' ${u.enlaceMaps}');
    return MensajeAlerta(whatsapp: w.toString(), sms: textoSms(s.toString()));
  }

  static MensajeAlerta _aSalvo(String nombre, DatosUbicacion? u, DateTime fecha) {
    final w = StringBuffer()
      ..writeln('✅ *$nombre YA ESTÁ A SALVO*')
      ..writeln()
      ..writeln('La alerta de emergencia anterior queda cancelada. ¡Gracias por estar pendiente! 🙏');
    if (u != null) w.writeln('📍 ${u.enlaceMaps}');
    w.write('🕒 ${fechaHora(fecha)}');

    final s = StringBuffer(
      'TRANQUILO: $nombre YA ESTA A SALVO. La alerta anterior queda cancelada. Gracias.',
    );
    return MensajeAlerta(whatsapp: w.toString(), sms: textoSms(s.toString()));
  }

  /// Caracteres del alfabeto GSM-7 (SMS de 160 caracteres por parte).
  static const _gsm =
      '@£\$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?'
      '¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';

  static const _reemplazos = {
    'á': 'a', 'í': 'i', 'ó': 'o', 'ú': 'u', 'Á': 'A', 'Í': 'I', 'Ó': 'O',
    'Ú': 'U', 'È': 'E', 'Ê': 'E', 'ê': 'e', 'ç': 'c', '—': '-', '–': '-',
    '“': '"', '”': '"', '‘': "'", '’': "'", '±': '+-', '…': '...',
  };

  /// Convierte el texto al alfabeto GSM-7 (quita emojis y tildes no soportadas).
  static String textoSms(String texto) {
    final b = StringBuffer();
    for (final r in texto.runes) {
      final ch = String.fromCharCode(r);
      if (_gsm.contains(ch)) {
        b.write(ch);
      } else if (_reemplazos.containsKey(ch)) {
        b.write(_reemplazos[ch]);
      }
    }
    return b.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
  }
}
