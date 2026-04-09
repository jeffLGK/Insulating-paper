import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'camera_capture_screen.dart';
import 'image_match_providers.dart';
import 'match_result_screen.dart';

/// 圖像比對功能的入口畫面
class ImageMatchScreen extends ConsumerWidget {
  const ImageMatchScreen({super.key});

  // ── 權限 ──────────────────────────────────────────────────────

  Future<bool> _requestCameraPermission(BuildContext context) async {
    if (kIsWeb) return true;
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied && context.mounted) {
      _showPermissionDialog(context, '相機');
      return false;
    }
    return status.isGranted;
  }

  Future<bool> _requestPhotosPermission(BuildContext context) async {
    if (kIsWeb) return true;
    final status = await Permission.photos.request();
    if (status.isPermanentlyDenied && context.mounted) {
      _showPermissionDialog(context, '照片');
      return false;
    }
    return status.isGranted || status.isLimited;
  }

  void _showPermissionDialog(BuildContext context, String permType) {
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

  // ── 裁切 ──────────────────────────────────────────────────────

  Future<Uint8List?> _cropImage(
      String sourcePath, BuildContext context) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁切隔熱紙區域',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: Colors.greenAccent,
          initAspectRatio: CropAspectRatioPreset.ratio3x2,
          lockAspectRatio: false,
          showCropGrid: true,
          aspectRatioPresets: [
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
          ],
        ),
        IOSUiSettings(
          title: '裁切隔熱紙區域',
          doneButtonTitle: '確認',
          cancelButtonTitle: '取消',
          aspectRatioPresets: [
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
          ],
        ),
      ],
    );
    if (cropped == null) return null;
    return cropped.readAsBytes();
  }

  // ── 相機拍照流程 ───────────────────────────────────────────────

  Future<void> _startCamera(BuildContext context, WidgetRef ref) async {
    if (kIsWeb) {
      _showWebNotSupported(context);
      return;
    }
    final granted = await _requestCameraPermission(context);
    if (!granted || !context.mounted) return;

    // 開啟帶取景框的相機畫面，取得圖片 bytes
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (bytes == null || !context.mounted) return;

    // 存為暫存檔，供 image_cropper 使用
    final tmpDir = await getTemporaryDirectory();
    final tmpPath =
        '${tmpDir.path}/tint_query_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(tmpPath).writeAsBytes(bytes);

    if (!context.mounted) return;
    final croppedBytes = await _cropImage(tmpPath, context);
    if (croppedBytes == null || !context.mounted) return;

    await _doMatch(context, ref, croppedBytes);
  }

  // ── 上傳圖片流程 ───────────────────────────────────────────────

  Future<void> _startUpload(BuildContext context, WidgetRef ref) async {
    if (kIsWeb) {
      _showWebNotSupported(context);
      return;
    }
    final granted = await _requestPhotosPermission(context);
    if (!granted || !context.mounted) return;

    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (xFile == null || !context.mounted) return;

    final croppedBytes = await _cropImage(xFile.path, context);
    if (croppedBytes == null || !context.mounted) return;

    await _doMatch(context, ref, croppedBytes);
  }

  // ── 執行比對並導向結果畫面 ───────────────────────────────────

  Future<void> _doMatch(
      BuildContext context, WidgetRef ref, Uint8List bytes) async {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MatchResultScreen()),
    );
    await ref.read(imageMatchProvider.notifier).startMatch(bytes);
  }

  void _showWebNotSupported(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('此功能僅支援手機平台')),
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageMatchProvider);
    final isLoading = state.status == MatchStatus.loading;

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
                      '1. 以相機對準玻璃上的隔熱紙標貼拍照，或上傳現有圖片。\n'
                      '2. 裁切框選目標標貼區域。\n'
                      '3. 系統自動與認證資料庫比對，顯示相似度前5名。\n'
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
              sublabel: '開啟相機，對準框內拍攝',
              color: Colors.blue,
              onTap: isLoading ? null : () => _startCamera(context, ref),
            ),

            const SizedBox(height: 16),

            // 上傳按鈕
            _BigButton(
              icon: Icons.photo_library_rounded,
              label: '上傳圖片',
              sublabel: '從相簿或檔案選取',
              color: Colors.teal,
              onTap: isLoading ? null : () => _startUpload(context, ref),
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
