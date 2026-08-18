import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class EmergenciaProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool _hasPermission = false;
  String _mensaje = 'Presiona el botón en caso de emergencia';
  Position? _ubicacion;
  List<String> _contactos = [];

  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  String get mensaje => _mensaje;
  Position? get ubicacion => _ubicacion;
  List<String> get contactos => _contactos;

  EmergenciaProvider() {
    _cargarContactos();
  }

  Future<void> _cargarContactos() async {
    final prefs = await SharedPreferences.getInstance();
    _contactos = prefs.getStringList('contactosEmergencia') ?? [];
    notifyListeners();
  }

  Future<void> guardarContactos(List<String> nuevosContactos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('contactosEmergencia', nuevosContactos);
    _contactos = nuevosContactos;
    notifyListeners();
  }

  Future<void> verificarPermisos() async {
    _isLoading = true;
    notifyListeners();

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      _hasPermission = permission == LocationPermission.always || 
                      permission == LocationPermission.whileInUse;
      
      if (_hasPermission) {
        _mensaje = '✅ Permisos concedidos - Listo para emergencias';
        await _obtenerUbicacion();
      } else {
        _mensaje = '⚠️ Permisos necesarios para enviar ubicación';
      }
      
    } catch (e) {
      _mensaje = '❌ Error al verificar permisos: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _obtenerUbicacion() async {
    try {
      _ubicacion = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _mensaje = '📍 Ubicación obtenida correctamente';
    } catch (e) {
      _mensaje = '⚠️ No se pudo obtener ubicación: $e';
    }
    notifyListeners();
  }

  Future<void> enviarEmergencia(BuildContext context) async {
    if (!_hasPermission) {
      await verificarPermisos();
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
    _mensaje = '🚨 Enviando alerta de emergencia...';
    notifyListeners();

    try {
      await _obtenerUbicacion();
      
      if (_ubicacion == null) {
        throw Exception('No se pudo obtener la ubicación');
      }

      final mensajeEmergencia = '''
🚨 ¡ALERTA DE EMERGENCIA! 
📍 Mi ubicación: 
https://www.google.com/maps?q=${_ubicacion!.latitude},${_ubicacion!.longitude}

📱 App de Emergencia - Botón de Pánico
''';

      for (var contacto in _contactos) {
        final whatsappUrl = Uri.parse(
          'https://wa.me/$contacto?text=${Uri.encodeComponent(mensajeEmergencia)}'
        );
        
        if (await canLaunchUrl(whatsappUrl)) {
          await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
        }
      }

      _mensaje = '✅ ¡Alerta enviada a ${_contactos.length} contactos!';
      _mostrarExito(context);

    } catch (e) {
      _mensaje = '❌ Error al enviar alerta: $e';
      _mostrarError(context, 'Error al enviar: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  void _mostrarExito(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚨 ¡ALERTA ENVIADA! Tus contactos han sido notificados'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 4),
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EmergenciaProvider()..verificarPermisos(),
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
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(16),
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
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Contactos de emergencia: ${provider.contactos.length}',
                    style: TextStyle(
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            Expanded(
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return GestureDetector(
                      onTap: () => _handleEmergencia(context, provider),
                      onLongPress: () => _handleEmergencia(context, provider),
                      child: Transform.scale(
                        scale: 1.0 + (0.03 * _pulseController.value),
                        child: Container(
                          width: 280,
                          height: 280,
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
                                      size: 80,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      '¡EMERGENCIA!',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Presiona para pedir ayuda',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    SizedBox(height: 30),
                                  ],
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text(
                    '⚠️ Solo usar en caso de emergencia real',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (provider.ubicacion != null)
                    Text(
                      '📍 ${provider.ubicacion!.latitude.toStringAsFixed(6)}, ${provider.ubicacion!.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleEmergencia(BuildContext context, EmergenciaProvider provider) async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 200);
    }
    
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('🚨 Confirmar emergencia'),
        content: const Text(
          '¿Estás seguro que deseas enviar una alerta de emergencia?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enviar alerta'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await provider.enviarEmergencia(context);
    }
  }

  void _irConfiguracion(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ConfiguracionDialog(),
    );
  }
}

class ConfiguracionDialog extends StatefulWidget {
  const ConfiguracionDialog({super.key});

  @override
  State<ConfiguracionDialog> createState() => _ConfiguracionDialogState();
}

class _ConfiguracionDialogState extends State<ConfiguracionDialog> {
  final TextEditingController _telefonoController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<EmergenciaProvider>(context);
    
    return AlertDialog(
      title: const Text('⚙️ Configuración'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contactos de emergencia:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...provider.contactos.map((contacto) => 
              ListTile(
                dense: true,
                leading: const Icon(Icons.person, color: Colors.blue),
                title: Text(contacto),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () {
                    final nuevos = List<String>.from(provider.contactos)
                      ..remove(contacto);
                    provider.guardarContactos(nuevos);
                  },
                ),
              ),
            ),
            if (provider.contactos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'No hay contactos configurados',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            const Divider(),
            const Text(
              'Agregar contacto:',
              style: TextStyle(fontWeight: FontWeight.bold),
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
                      final nuevos = List<String>.from(provider.contactos)
                        ..add(_telefonoController.text);
                      provider.guardarContactos(nuevos);
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
            const SizedBox(height: 8),
            const Text(
              '💡 Ejemplo: 573001234567 (Colombia)',
              style: TextStyle(fontSize: 10, color: Colors.grey),
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
    _telefonoController.dispose();
    super.dispose();
  }
}
