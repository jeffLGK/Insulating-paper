import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img_lib;

import 'widgets/viewfinder_overlay.dart';

// ── 頂層 isolate 裁切函式 ──────────────────────────────────────────
// compute() 需要頂層函式，無法使用 instance method。

Uint8List _doCrop(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  final frameLeft = args[1] as double;
  final frameTop = args[2] as double;
  final frameW = args[3] as double;
  final frameH = args[4] as double;
  final screenW = args[5] as double;
  final screenH = args[6] as double;

  final decoded = img_lib.decodeImage(bytes);
  if (decoded == null) return bytes;

  final scaleX = decoded.width / screenW;
  final scaleY = decoded.height / screenH;

  final x = (frameLeft * scaleX).round().clamp(0, decoded.width - 1);
  final y = (frameTop * scaleY).round().clamp(0, decoded.height - 1);
  final w = (frameW * scaleX).round().clamp(1, decoded.width - x);
  final h = (frameH * scaleY).round().clamp(1, decoded.height - y);

  final cropped = img_lib.copyCrop(decoded, x: x, y: y, width: w, height: h);
  return Uint8List.fromList(img_lib.encodeJpg(cropped, quality: 90));
}

// ── 相機畫面 ──────────────────────────────────────────────────────

/// 帶可調整取景框的相機畫面。
/// 使用者可任意縮放取景框，拍照後自動裁切至框內範圍，
/// 將裁切後的 Uint8List 回傳給呼叫方（不需要再次裁切）。
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing = false;
  FlashMode _flashMode = FlashMode.off;
  String? _errorMsg;

  /// 取景框目前座標（螢幕 dp），由 ResizableViewfinderOverlay 更新。
  final _frameNotifier = ValueNotifier<Rect?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _errorMsg = '未找到可用相機');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) return;
      _controller = controller;
      setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _errorMsg = '相機初始化失敗：$e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
      _controller = null;
      if (mounted) setState(() => _isInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _capture() async {
    if (!_isInitialized || _isCapturing || _controller == null) return;
    setState(() => _isCapturing = true);
    try {
      final xFile = await _controller!.takePicture();
      final fullBytes = await File(xFile.path).readAsBytes();

      // 依取景框範圍自動裁切（在背景 isolate 執行，不阻塞 UI）
      final frame = _frameNotifier.value;
      Uint8List resultBytes;
      if (frame != null) {
        final screenSize = MediaQuery.of(context).size;
        resultBytes = await compute(_doCrop, [
          fullBytes,
          frame.left,
          frame.top,
          frame.width,
          frame.height,
          screenSize.width,
          screenSize.height,
        ]);
      } else {
        resultBytes = fullBytes;
      }

      if (mounted) Navigator.of(context).pop<Uint8List>(resultBytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    final next =
        _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await _controller!.setFlashMode(next);
    setState(() => _flashMode = next);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameNotifier.dispose();
    _controller?.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _errorMsg != null
          ? _buildError()
          : !_isInitialized
              ? _buildLoading()
              : _buildCamera(),
    );
  }

  Widget _buildLoading() => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined,
                color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(
              _errorMsg!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('返回', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _buildCamera() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 相機預覽
        CameraPreview(_controller!),

        // 可調整大小的取景框 overlay（使用者可任意縮放）
        ResizableViewfinderOverlay(frameNotifier: _frameNotifier),

        // 頂部控制列
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _iconBtn(
                    icon: Icons.close,
                    onTap: () => Navigator.pop(context),
                  ),
                  _iconBtn(
                    icon: _flashMode == FlashMode.torch
                        ? Icons.flash_on
                        : Icons.flash_off,
                    onTap: _toggleFlash,
                  ),
                ],
              ),
            ),
          ),
        ),

        // 提示文字
        Positioned(
          bottom: 140,
          left: 16,
          right: 16,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '僅限拍攝申請者自行烙印的標貼',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '拖曳角落調整框大小，對準標貼後拍攝',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),

        // 拍攝按鈕
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Center(
                child: GestureDetector(
                  onTap: _capture,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      color: _isCapturing
                          ? Colors.white38
                          : Colors.white.withOpacity(0.92),
                    ),
                    child: _isCapturing
                        ? const Center(
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.black54,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _iconBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}
