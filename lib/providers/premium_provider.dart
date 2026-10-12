import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Compra única "AlertaYa Premium" mediante Google Play Billing.
///
/// * El producto se crea en Play Console → Monetizar → Productos →
///   Productos integrados en la aplicación, con el ID [idProducto].
/// * La compra solo funciona cuando la app se instala desde Play Store
///   (aunque sea en una pista de prueba cerrada).
/// * Para probar las funciones Premium con una APK instalada a mano, compila
///   con:  flutter build apk --release --dart-define=PREMIUM_PRUEBA=true
class PremiumProvider extends ChangeNotifier {
  /// [conectarTienda] = false se usa en las pruebas automáticas.
  PremiumProvider({bool conectarTienda = true}) {
    _iniciar(conectarTienda);
  }

  static const idProducto = 'alertaya_premium';
  static const _clave = 'premium_activo';

  /// Activado con --dart-define=PREMIUM_PRUEBA=true (solo para pruebas).
  static const modoPrueba = bool.fromEnvironment('PREMIUM_PRUEBA');

  InAppPurchase get _tienda => InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _suscripcion;

  bool _esPremium = modoPrueba;
  bool _tiendaDisponible = false;
  bool _procesando = false;
  ProductDetails? _producto;
  String? _mensaje;

  bool get esPremium => _esPremium;
  bool get tiendaDisponible => _tiendaDisponible;
  bool get procesando => _procesando;
  String? get mensaje => _mensaje;

  /// Precio en la moneda local que muestra Google Play (ej. "$ 9.900").
  String? get precio => _producto?.price;

  Future<void> _iniciar(bool conectarTienda) async {
    // 1. Lo que se sabe sin internet (compra hecha antes).
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_clave) == true) _esPremium = true;
    } catch (_) {}
    notifyListeners();
    if (!conectarTienda) return;

    // 2. Conectar con Google Play.
    try {
      _suscripcion = _tienda.purchaseStream.listen(
        _alActualizarCompras,
        onError: (Object e) => _ponerMensaje('Error de Google Play: $e'),
      );
      _tiendaDisponible = await _tienda.isAvailable();
      if (!_tiendaDisponible) {
        notifyListeners();
        return;
      }
      final r = await _tienda.queryProductDetails({idProducto});
      if (r.productDetails.isNotEmpty) _producto = r.productDetails.first;
      notifyListeners();
      // Recupera compras hechas en otro celular o tras reinstalar.
      await _tienda.restorePurchases();
    } catch (e) {
      debugPrint('Premium: $e');
      _tiendaDisponible = false;
      notifyListeners();
    }
  }

  Future<void> comprar() async {
    if (_esPremium) return;
    if (!_tiendaDisponible) {
      _ponerMensaje('Google Play no está disponible. Instala AlertaYa desde Play Store para comprar.');
      return;
    }
    final producto = _producto;
    if (producto == null) {
      _ponerMensaje('El producto Premium aún no está disponible en Google Play.');
      return;
    }
    _procesando = true;
    _mensaje = null;
    notifyListeners();
    try {
      await _tienda.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: producto));
    } catch (e) {
      _procesando = false;
      _ponerMensaje('No se pudo iniciar la compra: $e');
    }
  }

  Future<void> restaurar() async {
    if (!_tiendaDisponible) {
      _ponerMensaje('Google Play no está disponible en este celular.');
      return;
    }
    _procesando = true;
    _mensaje = null;
    notifyListeners();
    try {
      await _tienda.restorePurchases();
      // Si no hay compras, Play no responde nada: liberamos el botón.
      await Future<void>.delayed(const Duration(seconds: 4));
      if (_procesando) {
        _procesando = false;
        _ponerMensaje(_esPremium ? null : 'No se encontraron compras anteriores en esta cuenta.');
      }
    } catch (e) {
      _procesando = false;
      _ponerMensaje('No se pudieron restaurar las compras: $e');
    }
  }

  Future<void> _alActualizarCompras(List<PurchaseDetails> compras) async {
    for (final c in compras) {
      if (c.productID != idProducto) continue;
      switch (c.status) {
        case PurchaseStatus.pending:
          _procesando = true;
          _mensaje = 'Pago pendiente… se activará cuando Google Play lo confirme.';
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _activar();
          _procesando = false;
          _mensaje = '⭐ ¡Premium activado! Gracias por apoyar AlertaYa.';
        case PurchaseStatus.error:
          _procesando = false;
          _mensaje = 'La compra no se completó: ${c.error?.message ?? 'error desconocido'}';
        case PurchaseStatus.canceled:
          _procesando = false;
          _mensaje = 'Compra cancelada.';
      }
      if (c.pendingCompletePurchase) {
        try {
          await _tienda.completePurchase(c);
        } catch (e) {
          debugPrint('completePurchase: $e');
        }
      }
    }
    notifyListeners();
  }

  Future<void> _activar() async {
    _esPremium = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_clave, true);
    } catch (_) {}
  }

  void _ponerMensaje(String? m) {
    _mensaje = m;
    notifyListeners();
  }

  void limpiarMensaje() {
    _mensaje = null;
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }
}
