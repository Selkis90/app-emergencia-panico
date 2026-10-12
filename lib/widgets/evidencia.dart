import 'dart:async';

import 'package:flutter/material.dart';

import '../services/nativo.dart';

enum TipoEvidencia { foto, video, audio }

extension on TipoEvidencia {
  String get nombre => switch (this) {
        TipoEvidencia.foto => 'foto',
        TipoEvidencia.video => 'video',
        TipoEvidencia.audio => 'audio',
      };

  String get mime => switch (this) {
        TipoEvidencia.foto => 'image/jpeg',
        TipoEvidencia.video => 'video/mp4',
        TipoEvidencia.audio => 'audio/mp4',
      };

  IconData get icono => switch (this) {
        TipoEvidencia.foto => Icons.photo_camera,
        TipoEvidencia.video => Icons.videocam,
        TipoEvidencia.audio => Icons.mic,
      };
}

class _Evidencia {
  final TipoEvidencia tipo;
  final String ruta;
  final DateTime hora;

  _Evidencia(this.tipo, this.ruta) : hora = DateTime.now();
}

/// Premium: tomar una foto, grabar un video o un audio durante la emergencia
/// y enviarlo por WhatsApp (o cualquier otra app) junto con la ubicación.
///
/// WhatsApp no permite enviar archivos de forma automática: se abre WhatsApp
/// con el archivo y el texto listos, y el usuario elige los chats o el grupo.
class TarjetaEvidencia extends StatefulWidget {
  const TarjetaEvidencia({
    super.key,
    required this.esPremium,
    required this.onBloqueado,
    required this.textoParaEnviar,
    this.paqueteWhatsApp,
  });

  final bool esPremium;

  /// Se llama cuando el usuario no es Premium (abre la pantalla de compra).
  final Future<void> Function() onBloqueado;

  /// Texto que acompaña el archivo (recibe "foto", "video" o "audio").
  final String Function(String tipo) textoParaEnviar;

  /// 'com.whatsapp', 'com.whatsapp.w4b' o null si no está instalado.
  final String? paqueteWhatsApp;

  /// Duración máxima de video y audio.
  static const segundosVideo = 60;
  static const minutosAudio = 5;

  @override
  State<TarjetaEvidencia> createState() => _TarjetaEvidenciaState();
}

class _TarjetaEvidenciaState extends State<TarjetaEvidencia> {
  final List<_Evidencia> _enviadas = [];
  bool _ocupado = false;
  bool _grabandoAudio = false;
  int _segundosAudio = 0;
  Timer? _reloj;

  @override
  void dispose() {
    _reloj?.cancel();
    if (_grabandoAudio) Nativo.cancelarAudio();
    super.dispose();
  }

  Future<void> _conPremium(Future<void> Function() accion) async {
    if (!widget.esPremium) {
      await widget.onBloqueado();
      return;
    }
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await accion();
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ------------------------------------------------------------------

  Future<void> _foto() => _conPremium(() async {
        final ruta = await Nativo.tomarFoto();
        if (ruta == null) {
          _aviso('No se tomó ninguna foto');
          return;
        }
        await _listo(_Evidencia(TipoEvidencia.foto, ruta));
      });

  Future<void> _video() => _conPremium(() async {
        final ruta = await Nativo.grabarVideo(segundos: TarjetaEvidencia.segundosVideo);
        if (ruta == null) {
          _aviso('No se grabó ningún video');
          return;
        }
        await _listo(_Evidencia(TipoEvidencia.video, ruta));
      });

  Future<void> _audio() async {
    if (_grabandoAudio) {
      await _detenerAudio();
      return;
    }
    await _conPremium(() async {
      var permiso = await Nativo.tienePermiso('microfono');
      if (!permiso) permiso = await Nativo.pedirPermiso('microfono');
      if (!permiso) {
        _aviso('Sin permiso de micrófono. Actívalo en los ajustes de la app.',
            accion: SnackBarAction(label: 'Ajustes', onPressed: Nativo.abrirAjustesApp));
        return;
      }
      if (!await Nativo.iniciarAudio()) {
        _aviso('No se pudo iniciar la grabación de audio');
        return;
      }
      Nativo.vibrarSos();
      if (!mounted) return;
      setState(() {
        _grabandoAudio = true;
        _segundosAudio = 0;
      });
      _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _segundosAudio++);
        if (_segundosAudio >= TarjetaEvidencia.minutosAudio * 60) _detenerAudio();
      });
    });
  }

  Future<void> _detenerAudio() async {
    _reloj?.cancel();
    _reloj = null;
    final ruta = await Nativo.detenerAudio();
    if (!mounted) return;
    setState(() => _grabandoAudio = false);
    if (ruta == null) {
      _aviso('El audio fue muy corto, graba al menos 2 segundos');
      return;
    }
    await _listo(_Evidencia(TipoEvidencia.audio, ruta));
  }

  Future<void> _cancelarAudio() async {
    _reloj?.cancel();
    _reloj = null;
    await Nativo.cancelarAudio();
    if (mounted) setState(() => _grabandoAudio = false);
  }

  /// Guarda la evidencia y abre WhatsApp de inmediato para enviarla.
  Future<void> _listo(_Evidencia e) async {
    if (!mounted) return;
    setState(() => _enviadas.insert(0, e));
    await _enviar(e, porWhatsApp: widget.paqueteWhatsApp != null);
  }

  Future<void> _enviar(_Evidencia e, {required bool porWhatsApp}) async {
    final ok = await Nativo.compartirArchivo(
      e.ruta,
      e.tipo.mime,
      widget.textoParaEnviar(e.tipo.nombre),
      paquete: porWhatsApp ? widget.paqueteWhatsApp : null,
    );
    if (!ok) _aviso('No se pudo abrir ${porWhatsApp ? 'WhatsApp' : 'una app para enviar'}');
  }

  void _aviso(String texto, {SnackBarAction? accion}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto), action: accion));
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');

  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final candado = widget.esPremium
        ? null
        : Icon(Icons.lock_outline, size: 16, color: Colors.amber.shade800);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text('Enviar evidencia',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
            if (candado != null) candado,
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Toma una foto, graba video o audio y se abre WhatsApp para enviarlo '
          'con tu ubicación a tus contactos o a un grupo.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 10),
        if (_grabandoAudio)
          _grabando()
        else
          Row(
            children: [
              _boton(TipoEvidencia.foto, 'Foto', _foto),
              const SizedBox(width: 8),
              _boton(TipoEvidencia.video, 'Video', _video),
              const SizedBox(width: 8),
              _boton(TipoEvidencia.audio, 'Audio', _audio),
            ],
          ),
        for (final e in _enviadas.take(3))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(e.tipo.icono, color: Colors.green.shade700),
            title: Text('${e.tipo.nombre[0].toUpperCase()}${e.tipo.nombre.substring(1)} '
                'de las ${_dos(e.hora.hour)}:${_dos(e.hora.minute)}'),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (widget.paqueteWhatsApp != null)
                  IconButton(
                    tooltip: 'Enviar por WhatsApp',
                    icon: const Icon(Icons.chat),
                    onPressed: () => _enviar(e, porWhatsApp: true),
                  ),
                IconButton(
                  tooltip: 'Enviar con otra app',
                  icon: const Icon(Icons.share),
                  onPressed: () => _enviar(e, porWhatsApp: false),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _boton(TipoEvidencia tipo, String texto, VoidCallback alTocar) {
    return Expanded(
      child: FilledButton.tonal(
        onPressed: _ocupado ? null : alTocar,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tipo.icono),
            const SizedBox(height: 4),
            Text(texto, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _grabando() {
    final tiempo = '${_dos(_segundosAudio ~/ 60)}:${_dos(_segundosAudio % 60)}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Grabando audio  $tiempo',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextButton(onPressed: _cancelarAudio, child: const Text('Cancelar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: _detenerAudio,
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Enviar'),
          ),
        ],
      ),
    );
  }
}
