import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/mensajes.dart';

enum EstadoGps { listo, gpsApagado, sinPermiso, permisoBloqueado, desconocido }

class ResultadoUbicacion {
  final DatosUbicacion? datos;
  final EstadoGps estado;

  const ResultadoUbicacion(this.datos, this.estado);
}

/// Obtiene la ubicación sin bloquear nunca la alerta: si no hay GPS o tarda
/// demasiado, usa la última ubicación conocida o envía sin ubicación.
class ServicioUbicacion {
  Future<EstadoGps> revisarEstado({bool pedirPermiso = false}) async {
    try {
      final activo = await Geolocator.isLocationServiceEnabled();
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied && pedirPermiso) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.deniedForever) {
        return EstadoGps.permisoBloqueado;
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.unableToDetermine) {
        return EstadoGps.sinPermiso;
      }
      if (!activo) return EstadoGps.gpsApagado;
      return EstadoGps.listo;
    } catch (e) {
      debugPrint('revisarEstado: $e');
      return EstadoGps.desconocido;
    }
  }

  Future<ResultadoUbicacion> obtener({
    Duration limite = const Duration(seconds: 12),
  }) async {
    final estado = await revisarEstado(pedirPermiso: true);
    if (estado == EstadoGps.sinPermiso || estado == EstadoGps.permisoBloqueado) {
      return ResultadoUbicacion(null, estado);
    }

    if (estado == EstadoGps.listo) {
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: limite,
          ),
        ).timeout(limite + const Duration(seconds: 2));
        return ResultadoUbicacion(_convertir(p, false), estado);
      } catch (e) {
        debugPrint('getCurrentPosition: $e');
      }
    }

    // Respaldo: última ubicación conocida.
    try {
      final ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null) {
        return ResultadoUbicacion(_convertir(ultima, true), estado);
      }
    } catch (e) {
      debugPrint('getLastKnownPosition: $e');
    }
    return ResultadoUbicacion(null, estado);
  }

  DatosUbicacion _convertir(Position p, bool ultima) => DatosUbicacion(
        latitud: p.latitude,
        longitud: p.longitude,
        precisionMetros: p.accuracy > 0 ? p.accuracy : null,
        fecha: p.timestamp,
        esUltimaConocida: ultima,
      );

  Future<bool> abrirAjustesGps() => Geolocator.openLocationSettings();

  Future<bool> abrirAjustesApp() => Geolocator.openAppSettings();
}
