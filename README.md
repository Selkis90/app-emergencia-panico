# 🆘 AlertaYa – Botón de pánico

App Android (Flutter) que, con un solo toque, envía una alerta **S.O.S.** con tu ubicación a tus
contactos de confianza por **SMS automático** y **WhatsApp**, y te deja llamar a la línea de
emergencias.

## Funciones gratis
- **Botón SOS** con cuenta regresiva para cancelar si lo tocaste por error.
- **SMS automático** a todos tus contactos (sin abrir la app de mensajes).
- **WhatsApp continuo**: abre el chat de cada contacto con el mensaje escrito, o envíalo a un grupo.
- **Ubicación** con enlace de Google Maps (si el GPS falla, usa la última conocida o envía sin ella).
- **Vibración S.O.S.**, **llamar** al 123 o a tu contacto principal, **"Estoy a salvo"** y **mensaje de prueba**.
- **Contactos** guardados en el teléfono (no se borran al cerrar la app), con buscador en la agenda.

## ⭐ Funciones Premium (pago único)
| Función | Qué hace |
|---|---|
| Ubicación en vivo | Después del S.O.S. reenvía tu ubicación por SMS cada 3, 5, 10 o 15 min (máx. 2 h). |
| Modo "Llegué bien" | Temporizador: si no confirmas que llegaste, envía el S.O.S. solo. |
| Sirena | Tono de emergencia a todo volumen (canal de alarma). |
| Linterna S.O.S. | La linterna parpadea ··· ——— ···. |

> La ubicación en vivo y el temporizador funcionan mientras AlertaYa esté abierta o en segundo plano.
> Si Android cierra la app, el temporizador se revisa apenas se vuelva a abrir.

## Compilar

Requisitos: Flutter 3.32 o superior y **Java 17** (`flutter config --jdk-dir=/usr/lib/jvm/java-17-openjdk-amd64`).

```bash
flutter pub get
flutter test
flutter build apk --release                                   # APK normal
flutter build apk --release --dart-define=PREMIUM_PRUEBA=true # APK con Premium activado para probar
flutter build appbundle --release                             # AAB para subir a Play Store
```
La APK queda en `build/app/outputs/flutter-apk/app-release.apk`.

**La compra Premium solo funciona si la app se instala desde Google Play** (aunque sea en prueba
cerrada). Para probar las funciones Premium con una APK instalada a mano, usa `PREMIUM_PRUEBA=true`.
**Nunca subas a Play Store una versión compilada con `PREMIUM_PRUEBA=true`.**

## Publicar en Play Store

### 1. Crear tu llave de firma (una sola vez)
```bash
keytool -genkey -v -keystore ~/alertaya-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias alertaya
```
Crea el archivo `android/key.properties` (no se sube a GitHub, ya está en `.gitignore`):
```
storePassword=TU_CLAVE
keyPassword=TU_CLAVE
keyAlias=alertaya
storeFile=/home/TU_USUARIO/alertaya-upload.jks
```
⚠️ Guarda una copia del `.jks` y las claves en un lugar seguro: sin ellos no podrás actualizar la app.

### 2. Producto Premium
En Play Console → **Monetizar → Productos → Productos integrados en la aplicación**, crea un
producto con el ID **`alertaya_premium`** y ponle precio.

### 3. Requisitos de Google
- Cuenta de desarrollador y verificación de identidad.
- Cuentas personales nuevas: prueba cerrada con **12 testers durante 14 días** antes de producción.
- Formulario de **permisos de SMS** (excepción "alertas de emergencia por SMS"), **política de
  privacidad** publicada y formulario de **Seguridad de los datos**.
- ID de la app: `com.selkis90.alertaya` (no se puede cambiar después de publicar).

## Permisos (Android)
| Permiso | Para qué |
|---|---|
| Ubicación | Enlace de Google Maps en la alerta |
| Contactos | Buscar contactos en la agenda |
| SMS | SMS automático y ubicación en vivo |
| Llamadas | Solo si activas la "llamada directa" |

**APK instalada fuera de Play Store (Android 13+):** si el permiso de SMS dice *"Configuración
restringida"*: Ajustes → Apps → AlertaYa → ⋮ → *Permitir configuración restringida*.

## Estructura
```
lib/
  main.dart                          Arranque, tema y providers
  models/                            Contacto y Ajustes
  providers/emergencia_provider.dart Contactos, ajustes y GPS
  providers/premium_provider.dart    Compra Premium (Google Play Billing)
  providers/proteccion_provider.dart Ubicación en vivo, "Llegué bien", sirena, linterna
  services/                          Guardado, GPS y puente con Android
  screens/                           Inicio, Contactos, Agenda, Envío, Ajustes, Premium
  widgets/                           Botón SOS, cuenta regresiva, tarjeta "Llegué bien"
  utils/                             Mensajes y números de teléfono
android/app/src/main/kotlin/com/selkis90/alertaya/MainActivity.kt   Código nativo
test/                                Pruebas
```

AlertaYa no reemplaza a la línea de emergencias. Ante un peligro inmediato, llama al 123.
