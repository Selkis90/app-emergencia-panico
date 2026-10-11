import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/contacto.dart';
import '../providers/emergencia_provider.dart';
import '../services/nativo.dart';
import '../utils/telefono.dart';

enum _Estado { cargando, sinPermiso, listo, error }

/// Buscador de contactos de la agenda del teléfono.
/// Devuelve (pop) cuántos contactos se guardaron.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final _busqueda = TextEditingController();
  _Estado _estado = _Estado.cargando;
  List<ContactoAgenda> _todos = [];
  List<ContactoAgenda> _visibles = [];
  final Map<String, ContactoAgenda> _seleccionados = {};
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  String _clave(ContactoAgenda c) => '${c.id}|${c.telefono}';

  Future<void> _cargar() async {
    setState(() => _estado = _Estado.cargando);
    var permiso = await Nativo.tienePermiso('contactos');
    if (!permiso) permiso = await Nativo.pedirPermiso('contactos');
    if (!mounted) return;
    if (!permiso) {
      setState(() => _estado = _Estado.sinPermiso);
      return;
    }
    try {
      final lista = await Nativo.obtenerContactos();
      if (!mounted) return;
      setState(() {
        _todos = lista;
        _estado = _Estado.listo;
        _filtrar(_busqueda.text);
      });
    } catch (_) {
      if (mounted) setState(() => _estado = _Estado.error);
    }
  }

  void _filtrar(String texto) {
    final q = sinTildes(texto.trim().toLowerCase());
    if (q.isEmpty) {
      _visibles = _todos;
      return;
    }
    final palabras = q.split(RegExp(r'\s+'));
    final digitos = Telefono.soloDigitos(q);
    _visibles = _todos.where((c) {
      final nombre = sinTildes(c.nombre.toLowerCase());
      if (palabras.every(nombre.contains)) return true;
      return digitos.length >= 3 && Telefono.soloDigitos(c.telefono).contains(digitos);
    }).toList();
  }

  Future<void> _guardar() async {
    if (_seleccionados.isEmpty || _guardando) return;
    setState(() => _guardando = true);
    final p = context.read<EmergenciaProvider>();
    final nuevos = _seleccionados.values
        .map((c) => Contacto(id: Contacto.generarId(), nombre: c.nombre, telefono: c.telefono))
        .toList();
    final agregados = await p.agregarContactos(nuevos);
    if (!mounted) return;
    Navigator.of(context).pop(agregados);
  }

  Widget _cuerpo(EmergenciaProvider p) {
    switch (_estado) {
      case _Estado.cargando:
        return const Center(child: CircularProgressIndicator());
      case _Estado.sinPermiso:
        return _SinPermiso(onReintentar: _cargar);
      case _Estado.error:
        return Center(
            child: TextButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('No se pudo leer la agenda. Reintentar'),
            ),
          );
      case _Estado.listo:
        return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  controller: _busqueda,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _filtrar(v)),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre o número…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _busqueda.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _busqueda.clear();
                              setState(() => _filtrar(''));
                            },
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                    isDense: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_visibles.length} de ${_todos.length} números',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
              ),
              Expanded(
                child: _visibles.isEmpty
                    ? const Center(child: Text('No se encontraron contactos'))
                    : ListView.builder(
                        itemCount: _visibles.length,
                        itemBuilder: (context, i) {
                          final c = _visibles[i];
                          final guardado = p.yaGuardado(c.telefono);
                          final clave = _clave(c);
                          final marcado = guardado || _seleccionados.containsKey(clave);
                          return CheckboxListTile(
                            value: marcado,
                            onChanged: guardado
                                ? null
                                : (v) => setState(() {
                                      if (v == true) {
                                        _seleccionados[clave] = c;
                                      } else {
                                        _seleccionados.remove(clave);
                                      }
                                    }),
                            secondary: CircleAvatar(
                              backgroundColor:
                                  guardado ? Colors.green.shade100 : Colors.blueGrey.shade50,
                              child: Text(
                                c.nombre.isEmpty
                                    ? '?'
                                    : String.fromCharCode(c.nombre.runes.first).toUpperCase(),
                              ),
                            ),
                            title: Text(c.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              guardado
                                  ? '${c.telefono} · Ya guardado'
                                  : (c.tipo.isEmpty ? c.telefono : '${c.telefono} · ${c.tipo}'),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EmergenciaProvider>();
    final n = _seleccionados.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(n == 0 ? 'Buscar en mi agenda' : '$n seleccionado${n == 1 ? '' : 's'}'),
        actions: [
          if (n > 0)
            IconButton(
              tooltip: 'Limpiar selección',
              icon: const Icon(Icons.deselect),
              onPressed: () => setState(_seleccionados.clear),
            ),
        ],
      ),
      body: _cuerpo(p),
      bottomNavigationBar: _estado == _Estado.listo
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: n == 0 || _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(n == 0
                      ? 'Selecciona contactos'
                      : 'Guardar $n contacto${n == 1 ? '' : 's'}'),
                ),
              ),
            )
          : null,
    );
  }
}

class _SinPermiso extends StatelessWidget {
  const _SinPermiso({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.contacts, size: 64, color: Colors.blue),
            const SizedBox(height: 12),
            const Text(
              'Para buscar en tu agenda, la app necesita permiso para leer tus contactos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Solo se leen en tu teléfono; no se envían a ningún servidor.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onReintentar, child: const Text('Dar permiso')),
            TextButton(
              onPressed: () => Nativo.abrirAjustesApp(),
              child: const Text('Abrir ajustes de la app'),
            ),
          ],
        ),
      ),
    );
  }
}
