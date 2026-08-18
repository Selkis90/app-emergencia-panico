import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:location/location.dart';
import 'package:vibration/vibration.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

// ============================================================
// MODELO DE CONTACTO
// ============================================================

class Contacto {
  String id;
  String nombre;
  String telefono;
  bool esEmergencia;

  Contacto({
    required this.id,
    required this.nombre,
    required this.telefono,
    this.esEmergencia = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'telefono': telefono,
      'esEmergencia': esEmergencia,
    };
  }

  factory Contacto.fromJson(Map<String, dynamic> json) {
    return Contacto(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      nombre: json['nombre'] ?? 'Contacto',
      telefono: json['telefono'] ?? '',
      esEmergencia: json['esEmergencia'] ?? false,
    );
  }
}

// ============================================================
// PROVIDER
// ============================================================

class EmergenciaProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool _hasPermission = false;
  String _mensaje = 'Presiona el botón en caso de emergencia';
  LocationData? _ubicacion;
  List<Contacto> _contactos = [];
  String _estadoUsuario = 'Estoy bien';
  String _ultimoMensaje = '';

  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  String get mensaje => _mensaje;
  LocationData? get ubicacion => _ubicacion;
  List<Contacto> get contactos => _contactos;
  String get estadoUsuario => _estadoUsuario;
  String get ultimoMensaje => _ultimoMensaje;

  final Location _location = Location();

  EmergenciaProvider() {
    _cargarContactos();
    _cargarEstado();
    _verificarPermisos();
  }

  Future<void> _cargarContactos() async {
    final prefs = await SharedPreferences.getInstance();
    final contactosJson = prefs.getStringList('contactosEmergencia') ?? [];
    _contactos = contactosJson
        .map((json) => Contacto.fromJson(json as Map<String, dynamic>))
        .toList();
    notifyListeners();
  }

  Future<void> guardarContactos() async {
    final prefs = await SharedPreferences.getInstance();
    final contactosJson = _contactos.map((c) => c.toJson()).toList();
    await prefs.setStringList(
      'contactosEmergencia',
      contactosJson.map((c) => c.toString()).toList(),
    );
    notifyListeners();
  }

  void agregarContacto(String nombre, String telefono) {
    final nuevoContacto = Contacto(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      nombre: nombre.isNotEmpty ? nombre : 'Contacto',
      telefono: telefono,
      esEmergencia: true,
    );
    _contactos.add(nuevoContacto);
    guardarContactos();
    notifyListeners();
  }

  void eliminarContacto(String id) {
    _contactos.removeWhere((c) => c.id == id);
    guardarContactos();
    notifyListeners();
  }

  void cambiarEstado(String nuevoEstado) {
    _estadoUsuario = nuevoEstado;
    _guardarEstado();
    notifyListeners();
  }

  Future<void> _cargarEstado() async {
    final prefs = await SharedPreferences.getInstance();
    _estadoUsuario = prefs.getString('estadoUsuario') ?? 'Estoy bien';
    notifyListeners();
  }

  Future<void> _guardarEstado() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('estadoUsuario', _estadoUsuario);
  }

  Future<void> _verificarPermisos() async {
    _isLoading = true;
    notifyListeners();

    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          _mensaje = '⚠️ Servicio de ubicación no disponible';
          _isLoading = false;
          notifyListeners();
          return;
        }
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          _mensaje = '⚠️ Permisos de ubicación denegados';
          _isLoading = false;
          notifyListeners();
          return;
        }
      }
      
      _hasPermission = true;
      _mensaje = '✅ Permisos concedidos - Listo para emergencias';
      await _obtenerUbicacion();
      
    } catch (e) {
      _mensaje = '❌ Error al verificar permisos: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _obtenerUbicacion() async {
    try {
      _ubicacion = await _location.getLocation();
      _mensaje = '📍 Ubicación obtenida correctamente';
    } catch (e) {
      _mensaje = '⚠️ No se pudo obtener ubicación: $e';
    }
    notifyListeners();
  }

  Future<void> enviarEmergencia(BuildContext context, {bool esPrueba = false}) async {
    if (!_hasPermission) {
      await _verificarPermisos();
      if (!_hasPermission) {
        _mostrarError(context, 'Permisos necesarios para enviar alerta');
        return;
      }
    }

    if (_contactos.isEmpty) {
      _mostrarError(context, 'No hay contactos de emergencia configurados');
      return;
    }

    _isLoading = true;
    _mensaje = esPrueba ? '🧪 Enviando mensaje de prueba...' : '🚨 Enviando alerta de emergencia...';
    notifyListeners();

    try {
      await _obtenerUbicacion();
      
      if (_ubicacion == null) {
        throw Exception('No se pudo obtener la ubicación');
      }

      final mensaje = esPrueba
          ? _construirMensajePrueba()
          : _construirMensajeEmergencia();

      _ultimoMensaje = mensaje;

      // Enviar a cada contacto
      int enviados = 0;
      for (var contacto in _contactos) {
        try {
          // Limpiar el número de teléfono
          String telefono = contacto.telefono.replaceAll(RegExp(r'[^0-9]'), '');
          if (telefono.startsWith('0')) {
            telefono = telefono.substring(1);
          }
          
          // Intentar abrir WhatsApp con el mensaje pre-cargado
          final whatsappUrl = Uri.parse(
            'https://api.whatsapp.com/send?phone=$telefono&text=${Uri.encodeComponent(mensaje)}'
          );
          
          if (await canLaunchUrl(whatsappUrl)) {
            await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
            enviados++;
            
            // Esperar un momento entre contactos
            await Future.delayed(const Duration(seconds: 2));
          } else {
            // Si WhatsApp no funciona, intentar SMS
            final smsUrl = Uri.parse(
              'sms:$telefono?body=${Uri.encodeComponent(mensaje)}'
            );
            if (await canLaunchUrl(smsUrl)) {
              await launchUrl(smsUrl, mode: LaunchMode.externalApplication);
              enviados++;
            }
          }
        } catch (e) {
          print('Error enviando a ${contacto.nombre}: $e');
        }
      }

      _mensaje = esPrueba
          ? '✅ Mensaje de prueba enviado a $enviados contactos'
          : '✅ ¡Alerta enviada a $enviados contactos!';
      
      _mostrarExito(context, esPrueba, enviados);

    } catch (e) {
      _mensaje = '❌ Error al enviar: $e';
      _mostrarError(context, 'Error al enviar: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  String _construirMensajeEmergencia() {
    return '''
🚨 ¡ALERTA DE EMERGENCIA! 

👤 Estado: $_estadoUsuario

📍 Mi ubicación: 
https://www.google.com/maps?q=${_ubicacion!.latitude},${_ubicacion!.longitude}

📱 App de Emergencia - Botón de Pánico
⚠️ SOLO USAR EN CASO DE EMERGENCIA REAL
''';
  }

  String _construirMensajePrueba() {
    return '''
🧪 MENSAJE DE PRUEBA - APP DE EMERGENCIA

✅ Estoy probando mi app de emergencia, todo bien

📍 Mi ubicación: 
https://www.google.com/maps?q=${_ubicacion!.latitude},${_ubicacion!.longitude}

📱 App de Emergencia - Botón de Pánico
''';
  }

  void _mostrarExito(BuildContext context, bool esPrueba, int enviados) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          esPrueba 
            ? '🧪 Mensaje de prueba enviado a $enviados contactos'
            : '🚨 ¡ALERTA ENVIADA! $enviados contactos notificados'
        ),
        backgroundColor: esPrueba ? Colors.blue : Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _mostrarError(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ $mensaje'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

// ============================================================
// PANTALLA PRINCIPAL
// ============================================================

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EmergenciaProvider(),
      child: MaterialApp(
        title: 'Botón de Pánico',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.red,
            primary: Colors.red,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<EmergenciaProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚨 Botón de Pánico'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _irConfiguracion(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusCard(provider),
            _buildEstadoUsuario(provider),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return GestureDetector(
                      onTap: () => _handleEmergencia(context, provider, false),
                      onLongPress: () => _handleEmergencia(context, provider, false),
                      child: Transform.scale(
                        scale: 1.0 + (0.03 * _pulseController.value),
                        child: Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            gradient: const RadialGradient(
                              colors: [
                                Color(0xFFF44336),
                                Color(0xFFB71C1C),
                              ],
                              stops: [0.0, 1.0],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.3),
                                blurRadius: 50,
                                spreadRadius: 20,
                              ),
                              BoxShadow(
                                color: Colors.red.shade900.withOpacity(0.4),
                                blurRadius: 80,
                                spreadRadius: 30,
                              ),
                            ],
                          ),
                          child: provider.isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 4,
                                  ),
                                )
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.warning_rounded,
                                      color: Colors.white,
                                      size: 60,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      '¡EMERGENCIA!',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Presiona para pedir ayuda',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            _buildBotonPrueba(provider),
            _buildFooter(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(EmergenciaProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: provider.hasPermission ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: provider.hasPermission ? Colors.green.shade300 : Colors.orange.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            provider.hasPermission ? Icons.check_circle : Icons.warning,
            color: provider.hasPermission ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.mensaje,
              style: TextStyle(
                color: provider.hasPermission ? Colors.green.shade800 : Colors.orange.shade800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoUsuario(EmergenciaProvider provider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Estado: ', style: TextStyle(fontWeight: FontWeight.bold)),
          _buildEstadoBoton(
            context,
            'Estoy bien',
            Icons.check_circle,
            Colors.green,
            provider.estadoUsuario == 'Estoy bien',
            () => provider.cambiarEstado('Estoy bien'),
          ),
          const SizedBox(width: 8),
          _buildEstadoBoton(
            context,
            'Necesito ayuda',
            Icons.help,
            Colors.red,
            provider.estadoUsuario == 'Necesito ayuda',
            () => provider.cambiarEstado('Necesito ayuda'),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoBoton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? Border.all(color: color, width: 2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonPrueba(EmergenciaProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ElevatedButton.icon(
        onPressed: provider.isLoading ? null : () => _handleEmergencia(context, provider, true),
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('🧪 Enviar mensaje de prueba'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(EmergenciaProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Text(
            'Contactos: ${provider.contactos.length}',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '⚠️ Solo usar en caso de emergencia real',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          if (provider.ubicacion != null)
            Text(
              '📍 ${provider.ubicacion!.latitude?.toStringAsFixed(6) ?? "N/A"}, ${provider.ubicacion!.longitude?.toStringAsFixed(6) ?? "N/A"}',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  void _handleEmergencia(BuildContext context, EmergenciaProvider provider, bool esPrueba) async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 200);
    }
    
    final titulo = esPrueba ? '🧪 Enviar mensaje de prueba' : '🚨 Confirmar emergencia';
    final mensaje = esPrueba
        ? '¿Enviar mensaje de prueba a tus contactos?'
        : '¿Estás seguro que deseas enviar una alerta de emergencia?';
    
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: esPrueba ? Colors.blue : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(esPrueba ? 'Enviar prueba' : 'Enviar alerta'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await provider.enviarEmergencia(context, esPrueba: esPrueba);
    }
  }

  void _irConfiguracion(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ConfiguracionDialog(),
    );
  }
}

// ============================================================
// CONFIGURACIÓN
// ============================================================

class ConfiguracionDialog extends StatefulWidget {
  const ConfiguracionDialog({super.key});

  @override
  State<ConfiguracionDialog> createState() => _ConfiguracionDialogState();
}

class _ConfiguracionDialogState extends State<ConfiguracionDialog> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<EmergenciaProvider>(context);
    
    return AlertDialog(
      title: const Text('⚙️ Configuración'),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contactos de emergencia:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (provider.contactos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'No hay contactos configurados',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ...provider.contactos.map((contacto) => 
              ListTile(
                dense: true,
                leading: const Icon(Icons.person, color: Colors.blue),
                title: Text(contacto.nombre),
                subtitle: Text(contacto.telefono),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () => provider.eliminarContacto(contacto.id),
                ),
              ),
            ),
            const Divider(),
            const Text(
              'Agregar contacto:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(
                hintText: 'Nombre del contacto',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _telefonoController,
                    decoration: const InputDecoration(
                      hintText: 'Número con código país',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (_telefonoController.text.isNotEmpty) {
                      provider.agregarContacto(
                        _nombreController.text,
                        _telefonoController.text,
                      );
                      _nombreController.clear();
                      _telefonoController.clear();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('➕'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '💡 Ejemplo: 573001234567 (Colombia)',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              '📌 El mensaje se abre en WhatsApp, debes presionar "Enviar"',
              style: TextStyle(fontSize: 11, color: Colors.orange),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }
}
