/// Utilidades para normalizar números de teléfono.
///
/// WhatsApp exige el número en formato internacional SIN "+" ni espacios
/// (ej. 573001234567). La versión anterior quitaba el código de país o no lo
/// agregaba, por eso WhatsApp abría "número no válido".
class Telefono {
  Telefono._();

  static String soloDigitos(String texto) => texto.replaceAll(RegExp(r'\D'), '');

  /// Devuelve el número en formato internacional solo con dígitos.
  ///
  /// * `+57 300 123 4567` → `573001234567`
  /// * `300 123 4567` (código 57) → `573001234567`
  /// * `0057 300...` → `57300...`
  /// * `0 300...` (cero troncal) → `57300...`
  static String internacional(String telefono, String codigoPais) {
    final t = telefono.trim();
    var d = soloDigitos(t);
    if (d.isEmpty) return '';
    final cp = soloDigitos(codigoPais);

    if (t.startsWith('+')) return d;
    if (d.startsWith('00')) return d.substring(2);
    if (cp.isEmpty) return d;

    // Ya trae el código de país (ej. 573001234567).
    if (d.startsWith(cp) && d.length >= 11) return d;

    // Cero troncal nacional (ej. 0 300 123 4567).
    d = d.replaceFirst(RegExp(r'^0+'), '');
    if (d.isEmpty) return '';
    return '$cp$d';
  }

  /// Formato E.164 con "+" (ideal para SMS y llamadas).
  static String e164(String telefono, String codigoPais) {
    final i = internacional(telefono, codigoPais);
    return i.isEmpty ? '' : '+$i';
  }

  /// Clave para detectar duplicados (últimos 10 dígitos).
  static String clave(String telefono) {
    final d = soloDigitos(telefono);
    return d.length <= 10 ? d : d.substring(d.length - 10);
  }

  static bool esValido(String telefono) => soloDigitos(telefono).length >= 7;

  /// Para mostrar en pantalla: +57 300 123 4567
  static String bonito(String telefono, String codigoPais) {
    final i = internacional(telefono, codigoPais);
    if (i.isEmpty) return telefono;
    final cp = soloDigitos(codigoPais);
    if (cp.isNotEmpty && i.startsWith(cp) && i.length - cp.length == 10) {
      final n = i.substring(cp.length);
      return '+$cp ${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6)}';
    }
    return '+$i';
  }
}

/// Quita tildes para que las búsquedas encuentren "Jose" y "José".
String sinTildes(String texto) {
  const con = 'áéíóúàèìòùäëïöüâêîôûÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÂÊÎÔÛñÑçÇ';
  const sin = 'aeiouaeiouaeiouaeiouAEIOUAEIOUAEIOUAEIOUnNcC';
  final b = StringBuffer();
  for (final r in texto.runes) {
    final ch = String.fromCharCode(r);
    final i = con.indexOf(ch);
    b.write(i >= 0 ? sin[i] : ch);
  }
  return b.toString();
}
