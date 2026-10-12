import 'package:flutter_test/flutter_test.dart';

import 'package:alertaya/models/ajustes.dart';
import 'package:alertaya/models/contacto.dart';
import 'package:alertaya/utils/mensajes.dart';
import 'package:alertaya/utils/telefono.dart';

void main() {
  group('Telefono', () {
    test('agrega el código de país a celulares colombianos', () {
      expect(Telefono.internacional('300 123 4567', '57'), '573001234567');
      expect(Telefono.internacional('(300) 123-4567', '57'), '573001234567');
    });

    test('respeta números que ya traen código', () {
      expect(Telefono.internacional('+57 300 123 4567', '57'), '573001234567');
      expect(Telefono.internacional('573001234567', '57'), '573001234567');
      expect(Telefono.internacional('0057 300 123 4567', '57'), '573001234567');
      expect(Telefono.internacional('+1 305 555 0101', '57'), '13055550101');
    });

    test('formato E.164 y bonito', () {
      expect(Telefono.e164('3001234567', '57'), '+573001234567');
      expect(Telefono.bonito('3001234567', '57'), '+57 300 123 4567');
    });

    test('clave detecta duplicados con y sin código', () {
      expect(Telefono.clave('+57 300 123 4567'), Telefono.clave('3001234567'));
    });

    test('sinTildes', () {
      expect(sinTildes('José Muñoz'), 'Jose Munoz');
    });
  });

  group('Contacto', () {
    test('se guarda y se recupera en JSON', () {
      final lista = [
        Contacto(id: Contacto.generarId(), nombre: 'Ana', telefono: '3001234567'),
        Contacto(id: Contacto.generarId(), nombre: 'Luis', telefono: '3109876543', principal: true),
      ];
      final texto = Contacto.codificarLista(lista);
      final leida = Contacto.decodificarLista(texto);
      expect(leida.length, 2);
      expect(leida[1].nombre, 'Luis');
      expect(leida[1].principal, isTrue);
    });

    test('ids únicos aunque se creen en el mismo instante', () {
      final ids = List.generate(50, (_) => Contacto.generarId()).toSet();
      expect(ids.length, 50);
    });

    test('recupera el formato dañado de la versión anterior', () {
      final c = Contacto.desdeFormatoAntiguo(
        '{id: 1712345, nombre: Mamá, telefono: +57 300 123 4567, esEmergencia: true}',
      );
      expect(c, isNotNull);
      expect(c!.nombre, 'Mamá');
      expect(c.telefono, '+57 300 123 4567');
    });

    test('datos corruptos no rompen la app', () {
      expect(Contacto.decodificarLista('esto no es json'), isEmpty);
      expect(Contacto.decodificarLista(null), isEmpty);
    });
  });

  group('Mensajes', () {
    const ajustes = Ajustes(nombreUsuario: 'Andrés', infoAdicional: 'Sangre O+');
    const u = DatosUbicacion(latitud: 4.60971, longitud: -74.08175, precisionMetros: 12.4);

    test('el mensaje de emergencia incluye nombre, mapa e info', () {
      final m = ConstructorMensajes.construir(
        tipo: TipoAlerta.emergencia,
        ajustes: ajustes,
        ubicacion: u,
        ahora: DateTime(2026, 10, 8, 22, 46),
      );
      expect(m.whatsapp, contains('Andrés'));
      expect(m.whatsapp, contains('https://maps.google.com/?q=4.609710,-74.081750'));
      expect(m.whatsapp, contains('±12 m'));
      expect(m.whatsapp, contains('Sangre O+'));
      expect(m.whatsapp, contains('123'));
      expect(m.sms, startsWith('SOS EMERGENCIA! Andrés'));
      expect(m.sms, contains('08/10/2026 22:46'));
    });

    test('el SMS no lleva emojis ni caracteres fuera de GSM-7', () {
      final m = ConstructorMensajes.construir(
        tipo: TipoAlerta.emergencia,
        ajustes: ajustes.copyWith(mensajePersonalizado: 'Ayúdenme 🙏 rápido'),
        ubicacion: u,
      );
      expect(m.sms.runes.every((r) => r < 0x2000), isTrue);
      expect(m.sms, contains('Ayudenme rapido'));
    });

    test('sin ubicación también se construye el mensaje', () {
      final m = ConstructorMensajes.construir(tipo: TipoAlerta.emergencia, ajustes: ajustes);
      expect(m.whatsapp, contains('no disponible'));
      expect(m.sms, contains('Ubicacion no disponible'));
    });

    test('el motivo del temporizador aparece en la alerta', () {
      final m = ConstructorMensajes.construir(
        tipo: TipoAlerta.emergencia,
        ajustes: ajustes,
        ubicacion: u,
        motivo: 'No confirmó que llegó bien a tiempo',
      );
      expect(m.whatsapp, contains('⏰ No confirmó que llegó bien a tiempo'));
      expect(m.sms, contains('No confirmo que llego bien a tiempo.'));
    });

    test('mensaje de ubicación en vivo', () {
      final m = ConstructorMensajes.actualizacion(
        ajustes: ajustes,
        ubicacion: u,
        numero: 3,
        ahora: DateTime(2026, 10, 8, 22, 46),
      );
      expect(m.whatsapp, contains('Ubicación en vivo #3'));
      expect(m.sms, startsWith('SOS ACTIVO Andrés - ubicacion #3: https://maps.google.com/?q=4.609710,-74.081750'));
    });

    test('ajustes Premium se guardan y recuperan', () {
      final a = Ajustes.decodificar(
        ajustes.copyWith(intervaloSeguimientoMin: 10, sirenaAutomatica: true).codificar(),
      );
      expect(a.intervaloSeguimientoMin, 10);
      expect(a.sirenaAutomatica, isTrue);
      expect(a.seguimientoAutomatico, isTrue);
    });

    test('ajustes se guardan y recuperan', () {
      final a = Ajustes.decodificar(ajustes.copyWith(segundosCuentaRegresiva: 10).codificar());
      expect(a.nombreUsuario, 'Andrés');
      expect(a.segundosCuentaRegresiva, 10);
    });
  });
}
