import 'package:flutter/material.dart';

/// Botón circular grande con pulso animado.
class BotonSos extends StatefulWidget {
  const BotonSos({
    super.key,
    required this.onPressed,
    this.tamano = 240,
    this.ocupado = false,
  });

  final VoidCallback? onPressed;
  final double tamano;
  final bool ocupado;

  @override
  State<BotonSos> createState() => _BotonSosState();
}

class _BotonSosState extends State<BotonSos> with SingleTickerProviderStateMixin {
  late final AnimationController _pulso = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tamano;
    return Semantics(
      button: true,
      label: 'Botón de emergencia S.O.S.',
      child: SizedBox(
        width: t * 1.35,
        height: t * 1.35,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Onda expansiva
            AnimatedBuilder(
              animation: _pulso,
              builder: (context, _) {
                final v = _pulso.value;
                return Container(
                  width: t * (1 + 0.35 * v),
                  height: t * (1 + 0.35 * v),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFD32F2F).withAlpha((90 * (1 - v)).round()),
                  ),
                );
              },
            ),
            Material(
              shape: const CircleBorder(),
              elevation: 10,
              shadowColor: const Color(0xFFB71C1C),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                width: t,
                height: t,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0xFFF44336), Color(0xFFB71C1C)],
                  ),
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.ocupado ? null : widget.onPressed,
                  child: Center(
                    child: widget.ocupado
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 4)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'SOS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: t * 0.26,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                ),
                              ),
                              Text(
                                'PEDIR AYUDA',
                                style: TextStyle(
                                  color: Colors.white.withAlpha(220),
                                  fontSize: t * 0.065,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
