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

  Contacto copyWith({
    String? id,
    String? nombre,
    String? telefono,
    bool? esEmergencia,
  }) {
    return Contacto(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      telefono: telefono ?? this.telefono,
      esEmergencia: esEmergencia ?? this.esEmergencia,
    );
  }
}
