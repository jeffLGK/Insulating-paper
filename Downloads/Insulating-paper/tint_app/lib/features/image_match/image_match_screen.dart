import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'camera_capture_screen.dart';
import 'image_match_providers.dart';
import 'match_result_screen.dart';

/// 圖像比對功能的入口畫面
class ImageMatchScreen extends ConsumerStatefulWidget {
  const ImageMatchScreen({super.key});

  @override
  ConsumerState<ImageMatchScreen> createState() => _ImageMatchScreenState();
}

class _ImageMatchScreenState extends ConsumerState<ImageMatchScreen> {
  /// 防止重複觸發（double-tap / 上傳回呼重複觸發）
  bool _processing = false;

  // ── 權限 ──────────────────────────────────────────────────────

  Future<bool> _requestCameraPermission() async {
    if (kIsWeb) return true;
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied && mounted) {
      _showPermissionDialog('相機');
      return false;
    }
    return status.isGranted;
  }

  Future<bool> _requestPhotosPermission() async {
    if (kIsWeb) return true;
    final status = await Permission.photos.request();
    if (status.isPermanentlyDenied && mounted) {
      _showPermissionDialog('照片');
      return false;
    }
    return status.isGranted || status.isLimited;
  }

  void _showPermissionDialog(String permType) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('需要$permType權限'),
        content: Text('請至系統設定開啟「$permType」權限，才能使用此功能。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('前往設定'),
          ),
        ],
      ),
    );
  }

  // ── 裁切（僅供上傳圖片使用） ──────────────────────────────────

  Future<Uint8List?> _cropImage(String sourcePath) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁切隔熱紙區域',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: Colors.greenAccent,
          lockAspectRatio: false,
          showCropGrid: true,
          aspectRatioPresets: [], // 空陣列：可自由裁切任意尺寸
        ),
        IOSUiSettings(
          title: '裁切隔熱紙區域',
          doneButtonTitle: '確認',
          cancelButtonTitle: '取消',
          aspectRatioPresets: [], // 空陣列：可自由裁切任意尺寸
        ),
      ],
    );
    if (cropped == null) return null;
    return cropped.readAsBytes();
  }

  // ── 相機拍照流程 ───────────────────────────────────────────────
  // 使用者在相機畫面內縮放取景框並拍照，相機畫面已自動裁切，
  // 回傳裁切好的 Uint8List，無需再次裁切，直接送比對。

  Future<void> _startCamera() async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      if (kIsWeb) {
        _showWebNotSupported();
        return;
      }
      final granted = await _requestCameraPermission();
      if (!granted || !mounted) return;

      // CameraCaptureScreen 已依取景框自動裁切，直接回傳 Uint8List
      final bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
      );
      if (bytes == null || !mounted) return;

      await _doMatch(bytes);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ── 上傳圖片流程 ───────────────────────────────────────────────
  // 從相簿選取後，讓使用者手動裁切標貼區域。

  Future<void> _startUpload() async {
    if (_processing) return; // 防止重複觸發
    setState(() => _processing = true);
    try {
      if (kIsWeb) {
        _showWebNotSupported();
        return;
      }
      final granted = await _requestPhotosPermission();
      if (!granted || !mounted) return;

      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (xFile == null || !mounted) return;

      final croppedBytes = await _cropImage(xFile.path);
      if (croppedBytes == null || !mounted) return;

      await _doMatch(croppedBytes);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ── 執行比對並導向結果畫面 ───────────────────────────────────

  Future<void> _doMatch(Uint8List bytes) async {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MatchResultScreen()),
    );
    await ref.read(imageMatchProvider.notifier).startMatch(bytes);
  }

  void _showWebNotSupported() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('此功能僅支援手機平台')),
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageMatchProvider);
    final isLoading = state.status == MatchStatus.loading;
    final disabled = isLoading || _processing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('圖像比對'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 說明文字
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Colors.blueGrey),
                        SizedBox(width: 8),
                        Text('使用說明',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. 拖曳取景框角落調整大小，對準隔熱紙標貼後拍照。\n'
                      '2. 或從相簿上傳圖片並裁切標貼區域。\n'
                      '3. 系統自動 OCR 辨識文字並與認證資料庫比對，顯示前5名。\n'
                      '4. 逐一檢視後，按「符合」查看完整資料。',
                      style: TextStyle(fontSize: 13, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // 拍照按鈕
            _BigButton(
              icon: Icons.camera_alt_rounded,
              label: '相機拍照',
              sublabel: '拖曳框線調整大小，對準標貼後拍攝',
              color: Colors.blue,
              onTap: disabled ? null : _startCamera,
            ),

            const SizedBox(height: 16),

            // 上傳按鈕
            _BigButton(
              icon: Icons.photo_library_rounded,
              label: '上傳圖片',
              sublabel: '從相簿或檔案選取',
              color: Colors.teal,
              onTap: disabled ? null : _startUpload,
            ),

            if (isLoading) ...[
              const SizedBox(height: 32),
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('比對中，請稍候…'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 大型操作按鈕 ────────────────────────────────────────────────

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback? onTap;

  const _BigButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return Material(
      color: active ? color.withOpacity(0.12) : Colors.grey.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: active
                      ? color.withOpacity(0.18)
                      : Colors.grey.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 30,
                  color: active ? color : Colors.grey,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: active ? color : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sublabel,
                      style: TextStyle(
                        fontSize: 13,
                        color: active
                            ? color.withOpacity(0.75)
                            : Colors.grey.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: active ? color : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
