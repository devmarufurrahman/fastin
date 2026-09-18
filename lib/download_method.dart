import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'colors.dart';
import 'storage_permission.dart';

// ✅ Android MediaStore scan — file টা Files app এ দেখানোর জন্য
const _mediaScanChannel = MethodChannel('com.fastnin.app/media_scanner');

Future<void> _triggerMediaScan(String filePath, String mimeType) async {
  try {
    await _mediaScanChannel.invokeMethod(
      'scanFile',
      {'filePath': filePath, 'mimeType': mimeType},
    );
    debugPrint('✅ MediaStore scan done: $filePath');
  } catch (e) {
    debugPrint('⚠️ MediaStore scan error: $e');
  }
}

Future<void> downloadAndSaveToGallery(
  String imageUrl,
  BuildContext context, {
  String? mimeType,
  String? suggestedFilename,
}) async {
  try {
    final isPermissionGranted = await requestPermission();
    if (!isPermissionGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // 📂 ১. চেক করা হচ্ছে এটি সাধারণ ইমেজ ফাইল নাকি অন্য কোনো ডকুমেন্ট/মিডিয়া ফাইল
    bool isImage =
        mimeType?.startsWith('image/') == true ||
        imageUrl.endsWith('.jpg') ||
        imageUrl.endsWith('.png') ||
        imageUrl.endsWith('.jpeg') ||
        imageUrl.endsWith('.webp') ||
        imageUrl.endsWith('.gif');

    if (isImage) {
      // ==================== আগের ইমেজ ডাউনলোড সিস্টেম (অক্ষুণ্ন রাখা হয়েছে) ====================
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloading Image...'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.orange,
          ),
        );
      }

      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        Uint8List bytes = response.bodyBytes;
        final result = await ImageGallerySaverPlus.saveImage(
          bytes,
          quality: 100,
          name: "my_qr_${DateTime.now().millisecondsSinceEpoch}",
        );

        if (context.mounted) {
          if (result['isSuccess'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Saved to Gallery!'),
                backgroundColor: AppColors.primaryColor,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Save failed!'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } else {
      // ==================== সর্বজনীন (Universal) ফাইল ডাউনলোড সিস্টেম ====================
      // Pdf, Doc, Zip, Mp4, Mp3 সহ যেকোনো ফাইল এখানে আসবে 🚀
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      final savedDir = directory?.path ?? '';
      final finalFilename =
          suggestedFilename ??
          "file_${DateTime.now().millisecondsSinceEpoch}.${imageUrl.split('.').last.split('?').first}";

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloading $finalFilename... Check notifications.'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      await FlutterDownloader.enqueue(
        url: imageUrl,
        savedDir: savedDir,
        fileName: finalFilename,
        showNotification: true,
        openFileFromNotification: true,
        saveInPublicStorage: true,
        requiresStorageNotLow: true,
      );
    }
  } catch (e) {
    debugPrint('Download error: $e');
  }
}

// ============================================================
//  saveBase64ToFile — PDF / Blob ফাইল Save করার জন্য
//  ✅ Fix: Temp → Downloads copy + Native Share dialog
//  Android 10+ এ MediaStore index ছাড়া file দেখা যায় না,
//  তাই Share dialog দিয়ে user নিজে যেখানে চায় save করবে।
// ============================================================
// ================================================================
//  saveBase64ToFile — PDF / Blob থেকে File Save
//  ✅ Fix: সরাসরি Downloads folder এ save + MediaStore scan
//  Android সব version এ কাজ করবে — Share dialog নেই
// ================================================================
Future<void> saveBase64ToFile(
  String base64String,
  BuildContext context, {
  String? mimeType,
  String? suggestedFilename,
}) async {
  try {
    // ── Step 1: base64 decode ──
    if (base64String.contains(',')) {
      base64String = base64String.split(',').last;
    }
    final Uint8List bytes =
        base64Decode(base64String.replaceAll(RegExp(r'\s+'), ''));

    // ── Step 2: File name ও extension ──
    final bool isPdf = mimeType?.contains('pdf') == true;
    final String ext = isPdf ? 'pdf' : 'bin';
    final String finalFilename =
        suggestedFilename ??
        "download_${DateTime.now().millisecondsSinceEpoch}.$ext";
    final String resolvedMime =
        isPdf ? 'application/pdf' : (mimeType ?? 'application/octet-stream');

    // ── Step 3: Downloads folder এ save ──
    Directory? dlDir;
    if (Platform.isAndroid) {
      dlDir = Directory('/storage/emulated/0/Download');
      if (!await dlDir.exists()) {
        await dlDir.create(recursive: true);
      }
      if (!await dlDir.exists()) {
        dlDir = await getExternalStorageDirectory();
      }
    } else {
      dlDir = await getApplicationDocumentsDirectory();
    }

    if (dlDir == null) {
      debugPrint('❌ Could not find download directory');
      return;
    }

    final File savedFile = File('${dlDir.path}/$finalFilename');
    await savedFile.writeAsBytes(bytes);
    final int fileSizeKb = (await savedFile.length()) ~/ 1024;
    debugPrint('✅ File saved: ${savedFile.path} (${fileSizeKb}KB)');

    if (!context.mounted) return;

    // ── Step 4: MediaStore scan — Files app এ সাথে সাথে দেখাবে ──
    await _triggerMediaScan(savedFile.path, resolvedMime);

    // ── Step 5: Snackbar with OPEN button ──
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.download_done, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$finalFilename (${fileSizeKb}KB)\nDownloads এ save হয়েছে!',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'OPEN',
            textColor: Colors.white,
            onPressed: () => _openFile(savedFile.path, resolvedMime),
          ),
        ),
      );
    }
  } catch (e) {
    debugPrint('Save base64 error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// ✅ PDF / File খোলার জন্য — FileProvider দিয়ে system PDF viewer launch করে
Future<void> _openFile(String filePath, String mimeType) async {
  try {
    await _mediaScanChannel.invokeMethod(
      'openFile',
      {'filePath': filePath, 'mimeType': mimeType},
    );
    debugPrint('✅ File opened: $filePath');
  } catch (e) {
    debugPrint('❌ Open file error: $e');
  }
}
