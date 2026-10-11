package com.emergencia.app_emergencia_panico

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.ContactsContract
import android.provider.Settings
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Puente nativo (Android) de la app de emergencia.
 *
 * Canal: "emergencia/nativo"
 *  - tienePermiso / pedirPermiso  (contactos, sms, llamada)
 *  - obtenerContactos             (lee la agenda del teléfono)
 *  - enviarSms                    (envía SMS automáticamente, sin abrir otra app)
 *  - abrirSms                     (abre la app de mensajes con todos los destinatarios)
 *  - whatsappInstalado / abrirChatWhatsApp / compartirWhatsApp
 *  - llamar                       (llamada directa o marcador)
 *  - vibrarSos / detenerVibracion
 *  - abrirAjustesApp
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CANAL = "emergencia/nativo"
        private const val CODIGO_PERMISO = 7301
        private const val WHATSAPP = "com.whatsapp"
        private const val WHATSAPP_BUSINESS = "com.whatsapp.w4b"
    }

    private var resultadoPermisoPendiente: MethodChannel.Result? = null
    private val hiloPrincipal = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL)
            .setMethodCallHandler { call, result ->
                try {
                    manejar(call, result)
                } catch (e: Exception) {
                    result.error("ERROR_NATIVO", e.message, null)
                }
            }
    }

    private fun manejar(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "tienePermiso" -> {
                val permiso = permisoAndroid(call.argument<String>("permiso"))
                result.success(permiso != null && concedido(permiso))
            }
            "pedirPermiso" -> pedirPermiso(call.argument<String>("permiso"), result)
            "obtenerContactos" -> obtenerContactos(result)
            "enviarSms" -> {
                val numeros = call.argument<List<String>>("numeros") ?: emptyList()
                val mensaje = call.argument<String>("mensaje") ?: ""
                result.success(enviarSms(numeros, mensaje))
            }
            "abrirSms" -> {
                val numeros = call.argument<List<String>>("numeros") ?: emptyList()
                val mensaje = call.argument<String>("mensaje") ?: ""
                result.success(abrirSms(numeros, mensaje))
            }
            "whatsappInstalado" -> result.success(
                mapOf(
                    "normal" to appInstalada(WHATSAPP),
                    "business" to appInstalada(WHATSAPP_BUSINESS)
                )
            )
            "abrirChatWhatsApp" -> {
                val telefono = call.argument<String>("telefono") ?: ""
                val mensaje = call.argument<String>("mensaje") ?: ""
                val paquete = call.argument<String>("paquete")
                result.success(abrirChatWhatsApp(telefono, mensaje, paquete))
            }
            "compartirWhatsApp" -> {
                val mensaje = call.argument<String>("mensaje") ?: ""
                val paquete = call.argument<String>("paquete")
                result.success(compartirWhatsApp(mensaje, paquete))
            }
            "llamar" -> {
                val numero = call.argument<String>("numero") ?: ""
                val directo = call.argument<Boolean>("directo") ?: false
                result.success(llamar(numero, directo))
            }
            "vibrarSos" -> {
                vibrarSos(call.argument<Int>("repeticiones") ?: 1)
                result.success(true)
            }
            "detenerVibracion" -> {
                vibrador()?.cancel()
                result.success(true)
            }
            "abrirAjustesApp" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                intent.data = Uri.parse("package:$packageName")
                result.success(iniciar(intent))
            }
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------------
    // PERMISOS
    // ------------------------------------------------------------------

    private fun permisoAndroid(nombre: String?): String? = when (nombre) {
        "contactos" -> Manifest.permission.READ_CONTACTS
        "sms" -> Manifest.permission.SEND_SMS
        "llamada" -> Manifest.permission.CALL_PHONE
        else -> null
    }

    private fun concedido(permiso: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return checkSelfPermission(permiso) == PackageManager.PERMISSION_GRANTED
    }

    private fun pedirPermiso(nombre: String?, result: MethodChannel.Result) {
        val permiso = permisoAndroid(nombre)
        if (permiso == null) {
            result.error("PERMISO_DESCONOCIDO", "Permiso no soportado: $nombre", null)
            return
        }
        if (concedido(permiso)) {
            result.success(true)
            return
        }
        if (resultadoPermisoPendiente != null) {
            result.error("PERMISO_EN_CURSO", "Ya hay una solicitud de permiso abierta", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        resultadoPermisoPendiente = result
        requestPermissions(arrayOf(permiso), CODIGO_PERMISO)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CODIGO_PERMISO) return
        val ok = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        resultadoPermisoPendiente?.success(ok)
        resultadoPermisoPendiente = null
    }

    // ------------------------------------------------------------------
    // CONTACTOS DE LA AGENDA
    // ------------------------------------------------------------------

    private fun obtenerContactos(result: MethodChannel.Result) {
        if (!concedido(Manifest.permission.READ_CONTACTS)) {
            result.error("SIN_PERMISO", "Permiso de contactos no concedido", null)
            return
        }
        // La agenda puede ser grande: se lee en un hilo aparte.
        Thread {
            try {
                val lista = ArrayList<Map<String, String>>()
                val columnas = arrayOf(
                    ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.TYPE,
                    ContactsContract.CommonDataKinds.Phone.LABEL
                )
                contentResolver.query(
                    ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    columnas,
                    null,
                    null,
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " COLLATE NOCASE ASC"
                )?.use { cursor ->
                    val iId = cursor.getColumnIndex(columnas[0])
                    val iNombre = cursor.getColumnIndex(columnas[1])
                    val iNumero = cursor.getColumnIndex(columnas[2])
                    val iTipo = cursor.getColumnIndex(columnas[3])
                    val iEtiqueta = cursor.getColumnIndex(columnas[4])
                    while (cursor.moveToNext()) {
                        val numero = if (iNumero >= 0) cursor.getString(iNumero) else null
                        if (numero.isNullOrBlank()) continue
                        val tipo = if (iTipo >= 0) cursor.getInt(iTipo) else 0
                        val etiqueta = if (iEtiqueta >= 0) cursor.getString(iEtiqueta) else null
                        val tipoTexto = ContactsContract.CommonDataKinds.Phone
                            .getTypeLabel(resources, tipo, etiqueta).toString()
                        lista.add(
                            mapOf(
                                "id" to (if (iId >= 0) cursor.getLong(iId).toString() else ""),
                                "nombre" to (if (iNombre >= 0) cursor.getString(iNombre) ?: "" else ""),
                                "telefono" to numero,
                                "tipo" to tipoTexto
                            )
                        )
                    }
                }
                hiloPrincipal.post { result.success(lista) }
            } catch (e: Exception) {
                hiloPrincipal.post { result.error("ERROR_CONTACTOS", e.message, null) }
            }
        }.start()
    }

    // ------------------------------------------------------------------
    // SMS
    // ------------------------------------------------------------------

    private fun smsManager(): SmsManager? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
    }

    /** Envía el SMS a cada número. Devuelve las listas de enviados y fallidos. */
    private fun enviarSms(numeros: List<String>, mensaje: String): Map<String, Any> {
        val enviados = ArrayList<String>()
        val fallidos = ArrayList<Map<String, String>>()

        if (!concedido(Manifest.permission.SEND_SMS)) {
            numeros.forEach { fallidos.add(mapOf("numero" to it, "error" to "Sin permiso de SMS")) }
            return mapOf("enviados" to enviados, "fallidos" to fallidos)
        }
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)) {
            numeros.forEach { fallidos.add(mapOf("numero" to it, "error" to "El equipo no tiene SIM/telefonía")) }
            return mapOf("enviados" to enviados, "fallidos" to fallidos)
        }

        val sms = smsManager()
        if (sms == null) {
            numeros.forEach { fallidos.add(mapOf("numero" to it, "error" to "Servicio SMS no disponible")) }
            return mapOf("enviados" to enviados, "fallidos" to fallidos)
        }

        for (numero in numeros) {
            try {
                val partes = sms.divideMessage(mensaje)
                if (partes.size > 1) {
                    sms.sendMultipartTextMessage(numero, null, partes, null, null)
                } else {
                    sms.sendTextMessage(numero, null, mensaje, null, null)
                }
                enviados.add(numero)
            } catch (e: Exception) {
                fallidos.add(mapOf("numero" to numero, "error" to (e.message ?: "Error desconocido")))
            }
        }
        return mapOf("enviados" to enviados, "fallidos" to fallidos)
    }

    /** Abre la app de mensajes con todos los destinatarios y el texto listo. */
    private fun abrirSms(numeros: List<String>, mensaje: String): Boolean {
        // Samsung usa coma como separador; el resto de fabricantes, punto y coma.
        val separador = if (Build.MANUFACTURER.equals("samsung", ignoreCase = true)) "," else ";"
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:" + numeros.joinToString(separador)))
        intent.putExtra("sms_body", mensaje)
        return iniciar(intent)
    }

    // ------------------------------------------------------------------
    // WHATSAPP
    // ------------------------------------------------------------------

    private fun appInstalada(paquete: String): Boolean {
        return try {
            packageManager.getLaunchIntentForPackage(paquete) != null
        } catch (e: Exception) {
            false
        }
    }

    private fun paqueteWhatsApp(preferido: String?): String? {
        if (preferido != null && appInstalada(preferido)) return preferido
        if (appInstalada(WHATSAPP)) return WHATSAPP
        if (appInstalada(WHATSAPP_BUSINESS)) return WHATSAPP_BUSINESS
        return null
    }

    /** Abre el chat de un número con el mensaje ya escrito (el usuario solo pulsa "enviar"). */
    private fun abrirChatWhatsApp(telefono: String, mensaje: String, preferido: String?): Boolean {
        val uri = Uri.parse(
            "https://api.whatsapp.com/send?phone=" + Uri.encode(telefono) +
                "&text=" + Uri.encode(mensaje)
        )
        val intent = Intent(Intent.ACTION_VIEW, uri)
        val paquete = paqueteWhatsApp(preferido)
        if (paquete != null) intent.setPackage(paquete)
        return iniciar(intent)
    }

    /** Abre WhatsApp para elegir uno o varios chats / grupos y reenviar el mensaje. */
    private fun compartirWhatsApp(mensaje: String, preferido: String?): Boolean {
        val intent = Intent(Intent.ACTION_SEND)
        intent.type = "text/plain"
        intent.putExtra(Intent.EXTRA_TEXT, mensaje)
        val paquete = paqueteWhatsApp(preferido)
        return if (paquete != null) {
            intent.setPackage(paquete)
            iniciar(intent)
        } else {
            iniciar(Intent.createChooser(intent, "Enviar alerta con…"))
        }
    }

    // ------------------------------------------------------------------
    // LLAMADAS
    // ------------------------------------------------------------------

    private fun llamar(numero: String, directo: Boolean): Boolean {
        val uri = Uri.parse("tel:" + Uri.encode(numero))
        if (directo && concedido(Manifest.permission.CALL_PHONE)) {
            if (iniciar(Intent(Intent.ACTION_CALL, uri))) return true
        }
        return iniciar(Intent(Intent.ACTION_DIAL, uri))
    }

    // ------------------------------------------------------------------
    // VIBRACIÓN S.O.S. ( · · ·  — — —  · · · )
    // ------------------------------------------------------------------

    private fun vibrador(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun vibrarSos(repeticiones: Int) {
        val v = vibrador() ?: return
        if (!v.hasVibrator()) return
        val punto = 200L
        val raya = 600L
        val pausa = 200L
        val pausaLetra = 600L
        val sos = longArrayOf(
            punto, pausa, punto, pausa, punto, pausaLetra,
            raya, pausa, raya, pausa, raya, pausaLetra,
            punto, pausa, punto, pausa, punto, 1200L
        )
        val patron = ArrayList<Long>()
        patron.add(0L)
        repeat(repeticiones.coerceIn(1, 5)) { patron.addAll(sos.toList()) }
        val arreglo = patron.toLongArray()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createWaveform(arreglo, -1))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(arreglo, -1)
        }
    }

    // ------------------------------------------------------------------

    private fun iniciar(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }
}
