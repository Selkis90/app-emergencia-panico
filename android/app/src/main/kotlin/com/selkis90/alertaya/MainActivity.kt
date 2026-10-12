package com.selkis90.alertaya

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.app.Activity
import android.content.ClipData
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.telephony.SmsManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Puente nativo (Android) de la app de emergencia.
 *
 * Canal: "alertaya/nativo"
 *  - tienePermiso / pedirPermiso  (contactos, sms, llamada)
 *  - obtenerContactos             (lee la agenda del teléfono)
 *  - enviarSms                    (envía SMS automáticamente, sin abrir otra app)
 *  - abrirSms                     (abre la app de mensajes con todos los destinatarios)
 *  - whatsappInstalado / abrirChatWhatsApp / compartirWhatsApp
 *  - llamar                       (llamada directa o marcador)
 *  - vibrarSos / detenerVibracion
 *  - sirena / linterna            (Premium: alarma sonora y linterna en S.O.S.)
 *  - tomarFoto / grabarVideo      (Premium: abre la cámara y devuelve la ruta del archivo)
 *  - iniciarAudio / detenerAudio / cancelarAudio (Premium: graba audio con el micrófono)
 *  - compartirArchivo             (Premium: envía foto/video/audio por WhatsApp u otra app)
 *  - abrirAjustesApp
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CANAL = "alertaya/nativo"
        private const val CODIGO_PERMISO = 7301
        private const val CODIGO_FOTO = 7302
        private const val CODIGO_VIDEO = 7303
        private const val CARPETA_EVIDENCIAS = "evidencias"
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
            "sirena" -> result.success(sirena(call.argument<Boolean>("activar") ?: false))
            "linterna" -> result.success(linterna(call.argument<Boolean>("activar") ?: false))
            "tomarFoto" -> abrirCamara(CODIGO_FOTO, result, 0)
            "grabarVideo" -> abrirCamara(CODIGO_VIDEO, result, call.argument<Int>("segundos") ?: 60)
            "iniciarAudio" -> result.success(iniciarAudio())
            "detenerAudio" -> result.success(detenerAudio(guardar = true))
            "cancelarAudio" -> {
                detenerAudio(guardar = false)
                result.success(true)
            }
            "compartirArchivo" -> result.success(
                compartirArchivo(
                    call.argument<String>("ruta") ?: "",
                    call.argument<String>("mime") ?: "*/*",
                    call.argument<String>("mensaje") ?: "",
                    call.argument<String>("paquete")
                )
            )
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
        "microfono" -> Manifest.permission.RECORD_AUDIO
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
    // SIRENA (Premium): tono de emergencia en el canal de ALARMA a todo volumen
    // ------------------------------------------------------------------

    private var tono: ToneGenerator? = null
    private var volumenAnterior: Int? = null
    private val repetirSirena = object : Runnable {
        override fun run() {
            val t = tono ?: return
            t.startTone(ToneGenerator.TONE_CDMA_EMERGENCY_RINGBACK, 2000)
            hiloPrincipal.postDelayed(this, 2000)
        }
    }

    private fun sirena(activar: Boolean): Boolean {
        val audio = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (!activar) {
            hiloPrincipal.removeCallbacks(repetirSirena)
            tono?.stopTone()
            tono?.release()
            tono = null
            val v = volumenAnterior
            if (audio != null && v != null) {
                try { audio.setStreamVolume(AudioManager.STREAM_ALARM, v, 0) } catch (e: Exception) { }
            }
            volumenAnterior = null
            return true
        }
        if (tono != null) return true
        return try {
            if (audio != null) {
                volumenAnterior = audio.getStreamVolume(AudioManager.STREAM_ALARM)
                audio.setStreamVolume(
                    AudioManager.STREAM_ALARM,
                    audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),
                    0
                )
            }
            tono = ToneGenerator(AudioManager.STREAM_ALARM, ToneGenerator.MAX_VOLUME)
            hiloPrincipal.post(repetirSirena)
            true
        } catch (e: Exception) {
            tono = null
            false
        }
    }

    // ------------------------------------------------------------------
    // LINTERNA S.O.S. (Premium): parpadea ··· ——— ··· sin parar
    // ------------------------------------------------------------------

    private var camaraFlash: String? = null
    private var pasoLinterna = 0
    private var linternaActiva = false
    // Duraciones encendido/apagado en ms: S (···) O (———) S (···) + pausa
    private val patronLinterna = longArrayOf(
        200, 200, 200, 200, 200, 600,
        600, 200, 600, 200, 600, 600,
        200, 200, 200, 200, 200, 1400
    )

    private val cicloLinterna = object : Runnable {
        override fun run() {
            if (!linternaActiva) return
            val encendida = pasoLinterna % 2 == 0
            ponerLinterna(encendida)
            val espera = patronLinterna[pasoLinterna]
            pasoLinterna = (pasoLinterna + 1) % patronLinterna.size
            hiloPrincipal.postDelayed(this, espera)
        }
    }

    private fun ponerLinterna(encendida: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val id = camaraFlash ?: return
        try {
            (getSystemService(Context.CAMERA_SERVICE) as? CameraManager)?.setTorchMode(id, encendida)
        } catch (e: Exception) { }
    }

    private fun linterna(activar: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        if (!activar) {
            linternaActiva = false
            hiloPrincipal.removeCallbacks(cicloLinterna)
            ponerLinterna(false)
            return true
        }
        if (linternaActiva) return true
        val camaras = getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return false
        camaraFlash = try {
            camaras.cameraIdList.firstOrNull { id ->
                camaras.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
        } catch (e: Exception) {
            null
        }
        if (camaraFlash == null) return false
        linternaActiva = true
        pasoLinterna = 0
        hiloPrincipal.post(cicloLinterna)
        return true
    }

    // ------------------------------------------------------------------
    // EVIDENCIA (Premium): foto, video y audio para enviar a los contactos
    // ------------------------------------------------------------------

    private var resultadoCamara: MethodChannel.Result? = null
    private var archivoCamara: File? = null

    /** Carpeta privada de la app; se borran las evidencias de más de 7 días. */
    private fun carpetaEvidencias(): File {
        val carpeta = File(filesDir, CARPETA_EVIDENCIAS)
        if (!carpeta.exists()) carpeta.mkdirs()
        val limite = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
        carpeta.listFiles()?.forEach { if (it.lastModified() < limite) it.delete() }
        return carpeta
    }

    private fun nuevoArchivo(prefijo: String, extension: String): File =
        File(carpetaEvidencias(), "${prefijo}_${System.currentTimeMillis()}.$extension")

    private fun uriDe(archivo: File): Uri =
        FileProvider.getUriForFile(this, "$packageName.archivos", archivo)

    /** Abre la app de cámara del celular. Devuelve a Flutter la ruta del archivo o null. */
    private fun abrirCamara(codigo: Int, result: MethodChannel.Result, segundos: Int) {
        if (resultadoCamara != null) {
            result.error("CAMARA_EN_CURSO", "La cámara ya está abierta", null)
            return
        }
        val esVideo = codigo == CODIGO_VIDEO
        val archivo = if (esVideo) nuevoArchivo("video", "mp4") else nuevoArchivo("foto", "jpg")
        val uri = uriDe(archivo)
        val intent = Intent(if (esVideo) MediaStore.ACTION_VIDEO_CAPTURE else MediaStore.ACTION_IMAGE_CAPTURE)
        intent.putExtra(MediaStore.EXTRA_OUTPUT, uri)
        if (esVideo) {
            intent.putExtra(MediaStore.EXTRA_DURATION_LIMIT, segundos.coerceIn(5, 300))
            // Calidad baja: el video pesa poco y llega rápido por WhatsApp.
            intent.putExtra(MediaStore.EXTRA_VIDEO_QUALITY, 0)
        }
        intent.clipData = ClipData.newRawUri("", uri)
        intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        resultadoCamara = result
        archivoCamara = archivo
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, codigo)
        } catch (e: Exception) {
            resultadoCamara = null
            archivoCamara = null
            result.error("SIN_CAMARA", "No se encontró una app de cámara: ${e.message}", null)
        }
    }

    @Deprecated("Se usa startActivityForResult por compatibilidad con FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CODIGO_FOTO && requestCode != CODIGO_VIDEO) return
        val result = resultadoCamara ?: return
        val archivo = archivoCamara
        resultadoCamara = null
        archivoCamara = null

        if (resultCode != Activity.RESULT_OK || archivo == null) {
            archivo?.delete()
            result.success(null)
            return
        }
        // Algunas cámaras ignoran EXTRA_OUTPUT en video y devuelven su propio archivo.
        if (archivo.length() == 0L) {
            val origen = data?.data
            if (origen != null) {
                try {
                    contentResolver.openInputStream(origen)?.use { entrada ->
                        archivo.outputStream().use { salida -> entrada.copyTo(salida) }
                    }
                } catch (e: Exception) { }
            }
        }
        if (archivo.exists() && archivo.length() > 0L) {
            result.success(archivo.absolutePath)
        } else {
            archivo.delete()
            result.success(null)
        }
    }

    private var grabadora: MediaRecorder? = null
    private var archivoAudio: File? = null

    /** Empieza a grabar audio (.m4a). Devuelve true si arrancó. */
    private fun iniciarAudio(): Boolean {
        if (grabadora != null) return true
        if (!concedido(Manifest.permission.RECORD_AUDIO)) return false
        val archivo = nuevoArchivo("audio", "m4a")
        return try {
            val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioSamplingRate(44100)
            r.setAudioEncodingBitRate(64000)
            r.setOutputFile(archivo.absolutePath)
            r.prepare()
            r.start()
            grabadora = r
            archivoAudio = archivo
            true
        } catch (e: Exception) {
            archivo.delete()
            grabadora = null
            archivoAudio = null
            false
        }
    }

    /** Detiene la grabación. Si [guardar] devuelve la ruta del audio (o null si falló). */
    private fun detenerAudio(guardar: Boolean): String? {
        val r = grabadora ?: return null
        val archivo = archivoAudio
        grabadora = null
        archivoAudio = null
        var ok = true
        try {
            r.stop()
        } catch (e: Exception) {
            // stop() falla si la grabación duró menos de ~1 segundo.
            ok = false
        }
        try { r.release() } catch (e: Exception) { }
        if (!guardar || !ok || archivo == null || archivo.length() == 0L) {
            archivo?.delete()
            return null
        }
        return archivo.absolutePath
    }

    /** Envía el archivo con un texto. [preferido] = paquete de WhatsApp, o null para elegir la app. */
    private fun compartirArchivo(ruta: String, mime: String, mensaje: String, preferido: String?): Boolean {
        val archivo = File(ruta)
        if (!archivo.exists()) return false
        val uri = uriDe(archivo)
        val intent = Intent(Intent.ACTION_SEND)
        intent.type = mime
        intent.putExtra(Intent.EXTRA_STREAM, uri)
        if (mensaje.isNotBlank()) intent.putExtra(Intent.EXTRA_TEXT, mensaje)
        intent.clipData = ClipData.newRawUri("", uri)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (preferido != null) {
            val paquete = paqueteWhatsApp(preferido)
            if (paquete != null) {
                intent.setPackage(paquete)
                if (iniciar(intent)) return true
                intent.setPackage(null)
            }
        }
        val selector = Intent.createChooser(intent, "Enviar evidencia con…")
        selector.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return iniciar(selector)
    }

    override fun onDestroy() {
        sirena(false)
        linterna(false)
        detenerAudio(guardar = false)
        super.onDestroy()
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
