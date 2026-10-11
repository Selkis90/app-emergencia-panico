import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/contacto.dart';
import '../providers/emergencia_provider.dart';
import '../services/nativo.dart';
import '../utils/telefono.dart';
import 'agenda_screen.dart';

/// Lista de contactos de emergencia guardados (con buscador).
class ContactosScreen extends StatefulWidget {
  const ContactosScreen({super.key});

  @override
  State<ContactosScreen> createState() => _ContactosScreenState();
}

class _ContactosScreenState extends State<ContactosScreen> {
  final _busqueda = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  List<Contacto> _filtrar(List<Contacto> lista) {
    final q = sinTildes(_filtro.trim().toLowerCase());
    if (q.isEmpty) return lista;
    final qDigitos = Telefono.soloDigitos(q);
    return lista.where((c) {
      if (sinTildes(c.nombre.toLowerCase()).contains(q)) return true;
      return qDigitos.length >= 3 && Telefono.soloDigitos(c.telefono).contains(qDigitos);
    }).toList();
  }

  Future<void> _mostrarOpcionesAgregar() async {
    final opcion = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (Nativo.esAndroid)
              ListTile(
                leading: const Icon(Icons.search, color: Colors.blue),
                title: const Text('Buscar en mi agenda'),
                subtitle: const Text('Busca por nombre o número y selecciona varios'),
                onTap: () => Navigator.pop(ctx, 'agenda'),
              ),
            ListTile(
              leading: const Icon(Icons.dialpad, color: Colors.green),
              title: const Text('Escribir número manualmente'),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || opcion == null) return;
    if (opcion == 'agenda') {
      final agregados = await Navigator.of(context).push<int>(
        MaterialPageRoute(builder: (_) => const AgendaScreen()),
      );
      if (!mounted || agregados == null || agregados == 0) return;
      _aviso('✅ $agregados contacto${agregados == 1 ? '' : 's'} guardado${agregados == 1 ? '' : 's'}');
    } else {
      await _editar(null);
    }
  }

  Future<void> _editar(Contacto? contacto) async {
    final p = context.read<EmergenciaProvider>();
    final r = await showDialog<Contacto>(
      context: context,
      builder: (_) => EditarContactoDialog(contacto: contacto, codigoPais: p.ajustes.codigoPais),
    );
    if (r == null || !mounted) return;
    if (contacto == null) {
      final ok = await p.agregarManual(r.nombre, r.telefono);
      if (!mounted) return;
      _aviso(ok ? '✅ Contacto guardado' : 'Ese número ya está en tu lista');
    } else {
      await p.actualizarContacto(r);
    }
  }

  Future<void> _eliminar(Contacto c) async {
    final p = context.read<EmergenciaProvider>();
    final posicion = p.contactos.indexWhere((x) => x.id == c.id);
    await p.eliminarContacto(c.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${c.nombre} eliminado'),
        action: SnackBarAction(
          label: 'DESHACER',
          onPressed: () => p.restaurarContacto(c, posicion),
        ),
      ));
  }

  void _aviso(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EmergenciaProvider>();
    final todos = p.contactos;
    final lista = _filtrar(todos);

    return Scaffold(
      appBar: AppBar(title: const Text('Contactos de emergencia')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarOpcionesAgregar,
        icon: const Icon(Icons.person_add),
        label: const Text('Agregar'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _busqueda,
              onChanged: (v) => setState(() => _filtro = v),
              decoration: InputDecoration(
                hintText: 'Buscar en mis contactos guardados',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filtro.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _busqueda.clear();
                          setState(() => _filtro = '');
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Se guardan en tu teléfono: no se borran al cerrar la app.',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: todos.isEmpty
                ? _Vacio(onAgregar: _mostrarOpcionesAgregar)
                : lista.isEmpty
                    ? const Center(child: Text('Sin resultados'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: lista.length,
                        itemBuilder: (context, i) {
                          final c = lista[i];
                          return Dismissible(
                            key: ValueKey(c.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) => _eliminar(c),
                            child: _TarjetaContacto(
                              contacto: c,
                              numero: p.numeroBonito(c),
                              onEditar: () => _editar(c),
                              onEliminar: () => _eliminar(c),
                              onPrincipal: () => p.marcarPrincipal(c.id),
                              onSms: (v) => p.actualizarContacto(c.copyWith(enviarSms: v)),
                              onWhatsApp: (v) => p.actualizarContacto(c.copyWith(enviarWhatsApp: v)),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaContacto extends StatelessWidget {
  const _TarjetaContacto({
    required this.contacto,
    required this.numero,
    required this.onEditar,
    required this.onEliminar,
    required this.onPrincipal,
    required this.onSms,
    required this.onWhatsApp,
  });

  final Contacto contacto;
  final String numero;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
  final VoidCallback onPrincipal;
  final ValueChanged<bool> onSms;
  final ValueChanged<bool> onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final c = contacto;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: c.principal ? Colors.amber : Colors.red.shade100,
                child: c.principal
                    ? const Icon(Icons.star, color: Colors.white)
                    : Text(c.inicial, style: TextStyle(color: Colors.red.shade900)),
              ),
              title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(c.principal ? '$numero · Principal (se llama primero)' : numero),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'principal':
                      onPrincipal();
                    case 'editar':
                      onEditar();
                    case 'eliminar':
                      onEliminar();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'principal',
                    child: Text(c.principal ? 'Quitar como principal' : 'Marcar como principal'),
                  ),
                  const PopupMenuItem(value: 'editar', child: Text('Editar')),
                  const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('SMS'),
                    avatar: const Icon(Icons.sms, size: 18),
                    selected: c.enviarSms,
                    onSelected: onSms,
                  ),
                  FilterChip(
                    label: const Text('WhatsApp'),
                    avatar: const Icon(Icons.chat, size: 18),
                    selected: c.enviarWhatsApp,
                    onSelected: onWhatsApp,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.onAgregar});

  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_add, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Aún no tienes contactos de emergencia',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Agrega familiares o amigos de confianza. Recibirán tu alerta por SMS y WhatsApp.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAgregar,
              icon: const Icon(Icons.person_add),
              label: const Text('Agregar contactos'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo para crear o editar un contacto. Devuelve el contacto resultante.
class EditarContactoDialog extends StatefulWidget {
  const EditarContactoDialog({super.key, this.contacto, required this.codigoPais});

  final Contacto? contacto;
  final String codigoPais;

  @override
  State<EditarContactoDialog> createState() => _EditarContactoDialogState();
}

class _EditarContactoDialogState extends State<EditarContactoDialog> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.contacto?.nombre ?? '');
  late final _telefono = TextEditingController(text: widget.contacto?.telefono ?? '');

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  void _guardar() {
    if (_form.currentState?.validate() != true) return;
    final nombre = _nombre.text.trim();
    final base = widget.contacto ??
        Contacto(id: Contacto.generarId(), nombre: nombre, telefono: _telefono.text.trim());
    Navigator.pop<Contacto>(
      context,
      base.copyWith(nombre: nombre.isEmpty ? 'Contacto' : nombre, telefono: _telefono.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.contacto == null ? 'Nuevo contacto' : 'Editar contacto'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telefono,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Número de celular',
                prefixIcon: const Icon(Icons.phone),
                helperText: 'Ej: 300 123 4567 (se agrega +${widget.codigoPais})',
              ),
              validator: (v) =>
                  Telefono.esValido(v ?? '') ? null : 'Escribe un número válido',
              onFieldSubmitted: (_) => _guardar(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
