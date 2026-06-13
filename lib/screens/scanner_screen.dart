import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final MobileScannerController cameraController = MobileScannerController();
  bool _isScanned = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Scanner
          MobileScanner(
            controller: cameraController,
            onDetect: (capture) {
              if (_isScanned) return;
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? code = barcodes.first.rawValue;
                if (code != null) {
                  _isScanned = true;
                  cameraController.stop();
                  Navigator.pop(context, code);
                }
              }
            },
          ),
          
          // Scanner Overlay Custom Paint
          LayoutBuilder(
            builder: (context, constraints) {
              final scanWindowWidth = constraints.maxWidth * 0.75;
              final scanWindow = Rect.fromCenter(
                center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
                width: scanWindowWidth,
                height: scanWindowWidth,
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: ScannerOverlayPainter(scanWindow: scanWindow),
                  ),
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: ScannerLinePainter(
                          scanWindow: scanWindow,
                          animationValue: _animationController.value,
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),

          // Top Controls (SafeArea respects notch)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildControlButton(
                    icon: Icons.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                  Row(
                    children: [
                      ValueListenableBuilder(
                        valueListenable: cameraController,
                        builder: (context, state, child) {
                          final isFlashOn = state.torchState == TorchState.on;
                          return _buildControlButton(
                            icon: isFlashOn ? Icons.flash_on : Icons.flash_off,
                            iconColor: isFlashOn ? Colors.yellow : Colors.white,
                            onPressed: () => cameraController.toggleTorch(),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      ValueListenableBuilder(
                        valueListenable: cameraController,
                        builder: (context, state, child) {
                          return _buildControlButton(
                            icon: Icons.flip_camera_ios,
                            onPressed: () => cameraController.switchCamera(),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom Instruction Text
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Scan QR Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Align the QR code within the frame to scan',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color iconColor = Colors.white,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor),
        onPressed: onPressed,
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;
  final double borderRadius;

  ScannerOverlayPainter({required this.scanWindow, this.borderRadius = 16.0});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(scanWindow, Radius.circular(borderRadius)));

    final path = Path.combine(PathOperation.difference, backgroundPath, cutoutPath);
    canvas.drawPath(path, backgroundPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final double cornerLength = 30.0;
    
    final cornerPath = Path();
    
    // Top Left
    cornerPath.moveTo(scanWindow.left, scanWindow.top + cornerLength);
    cornerPath.lineTo(scanWindow.left, scanWindow.top + borderRadius);
    cornerPath.arcToPoint(
      Offset(scanWindow.left + borderRadius, scanWindow.top),
      radius: Radius.circular(borderRadius),
      clockwise: true,
    );
    cornerPath.lineTo(scanWindow.left + cornerLength, scanWindow.top);

    // Top Right
    cornerPath.moveTo(scanWindow.right - cornerLength, scanWindow.top);
    cornerPath.lineTo(scanWindow.right - borderRadius, scanWindow.top);
    cornerPath.arcToPoint(
      Offset(scanWindow.right, scanWindow.top + borderRadius),
      radius: Radius.circular(borderRadius),
      clockwise: true,
    );
    cornerPath.lineTo(scanWindow.right, scanWindow.top + cornerLength);

    // Bottom Left
    cornerPath.moveTo(scanWindow.left, scanWindow.bottom - cornerLength);
    cornerPath.lineTo(scanWindow.left, scanWindow.bottom - borderRadius);
    cornerPath.arcToPoint(
      Offset(scanWindow.left + borderRadius, scanWindow.bottom),
      radius: Radius.circular(borderRadius),
      clockwise: false,
    );
    cornerPath.lineTo(scanWindow.left + cornerLength, scanWindow.bottom);

    // Bottom Right
    cornerPath.moveTo(scanWindow.right - cornerLength, scanWindow.bottom);
    cornerPath.lineTo(scanWindow.right - borderRadius, scanWindow.bottom);
    cornerPath.arcToPoint(
      Offset(scanWindow.right, scanWindow.bottom - borderRadius),
      radius: Radius.circular(borderRadius),
      clockwise: false,
    );
    cornerPath.lineTo(scanWindow.right, scanWindow.bottom - cornerLength);

    canvas.drawPath(cornerPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter oldDelegate) {
    return scanWindow != oldDelegate.scanWindow || borderRadius != oldDelegate.borderRadius;
  }
}

class ScannerLinePainter extends CustomPainter {
  final Rect scanWindow;
  final double animationValue;

  ScannerLinePainter({required this.scanWindow, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    // Prevent the line from going out of the border curve
    final double padding = 16.0; 
    final double workableHeight = scanWindow.height - (padding * 2);
    final double lineY = scanWindow.top + padding + (workableHeight * animationValue);
    
    final linePaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
      
    // Create a glowing effect
    final glowPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.5)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      
    final linePath = Path()
      ..moveTo(scanWindow.left + padding, lineY)
      ..lineTo(scanWindow.right - padding, lineY);
      
    canvas.drawPath(linePath, glowPaint);
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant ScannerLinePainter oldDelegate) {
    return scanWindow != oldDelegate.scanWindow || animationValue != oldDelegate.animationValue;
  }
}
