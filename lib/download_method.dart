import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'colors.dart';
import 'storage_permission.dart';

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
