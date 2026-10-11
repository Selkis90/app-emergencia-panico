# 🆘 Emergencia – Botón de Pánico

App Android (Flutter) que, con un solo toque, envía una alerta **S.O.S.** con tu
ubicación a tus contactos de confianza por **SMS automático** y **WhatsApp**, y te
deja llamar a la línea de emergencias.

## Funciones

- **Botón SOS** con cuenta regresiva para cancelar si lo tocaste por error (3, 5 o 10 s, o sin cuenta).
- **SMS automático**: se envía a todos tus contactos en segundo plano, sin abrir la app de mensajes.
  El texto va sin emojis ni tildes raras para que ocupe menos SMS.
- **WhatsApp continuo**: abre el chat de cada contacto con el mensaje ya escrito; tocas ➤ Enviar,
  vuelves a la app y se abre el siguiente. También puedes enviarlo a un **grupo**.
- **Ubicación** con enlace de Google Maps y precisión. Si el GPS falla, usa la última ubicación
  conocida o envía igual la alerta sin ubicación (la alerta nunca se bloquea).
- **Vibración S.O.S.** en código Morse (··· ——— ···).
- **Llamar** a la línea de emergencias (123) o a tu contacto principal.
- **"Estoy a salvo"**: avisa a todos que la alerta queda cancelada.
- **Mensaje de prueba** para comprobar que todo funciona.
- **Contactos**:
  - Buscador en la agenda del teléfono (por nombre o número, con o sin tildes) con selección múltiple.
  - Se guardan en el teléfono y **no se borran** al cerrar la app.
  - Buscador dentro de tus contactos guardados, editar, eliminar (con "Deshacer"), elegir contacto
    principal y activar/desactivar SMS o WhatsApp por contacto.
- **Ajustes**: tu nombre, mensaje personalizado, información médica (tipo de sangre, alergias…),
  código de país, línea de emergencias y permisos.

## Requisitos

- Flutter estable reciente (**3.32 o superior**) y JDK 17.
- Android 7.0 (API 24) o superior.

## Compilar

```bash
flutter clean
flutter pub get
flutter test
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`.

> Si cambias el ícono (`assets/images/imagen.png`): `dart run flutter_launcher_icons`

## Permisos (Android)

| Permiso | Para qué |
|---|---|
| Ubicación | Incluir el enlace de Google Maps en la alerta |
| Contactos | Buscar y elegir contactos de tu agenda |
| SMS | Enviar el SMS automático |
| Llamadas | Solo si activas la "llamada directa" |

**Android 13+ y APK instalado fuera de Play Store:** si al pedir el permiso de SMS aparece
*"Configuración restringida"*, ve a *Ajustes → Apps → Emergencia → ⋮ (arriba a la derecha) →
Permitir configuración restringida* y vuelve a darle el permiso.

**Play Store:** Google solo permite el permiso `SEND_SMS` a apps aprobadas mediante un formulario
de declaración. Para uso personal (instalando el APK) no hace falta.

## Estructura

```
lib/
  main.dart                      Arranque y tema
  models/contacto.dart           Contacto (JSON + migración del formato antiguo)
  models/ajustes.dart            Preferencias del usuario
  providers/emergencia_provider.dart  Estado global (contactos, ajustes, GPS)
  services/almacenamiento.dart   Guardado en el teléfono (SharedPreferences)
  services/nativo.dart           Puente con Android (agenda, SMS, WhatsApp, llamadas, vibración)
  services/ubicacion.dart        GPS con tiempo límite y respaldo
  utils/mensajes.dart            Textos de la alerta (WhatsApp y SMS)
  utils/telefono.dart            Normalización de números (+57…)
  screens/                       Inicio, Contactos, Agenda, Envío, Ajustes
  widgets/                       Botón SOS y cuenta regresiva
android/app/src/main/kotlin/.../MainActivity.kt   Código nativo Android
test/                            Pruebas
```

## Nota

WhatsApp no permite que otra app envíe mensajes sin que la persona toque "Enviar". Por eso el SMS
es el canal 100 % automático y WhatsApp funciona en modo continuo (un toque por contacto) o por grupo.
