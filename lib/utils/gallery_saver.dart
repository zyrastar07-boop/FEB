// lib/utils/gallery_saver.dart
import 'dart:io';
import 'package:gal/gal.dart';
import 'package:flutter/foundation.dart';

class GallerySaverResult {
  final bool success;
  final String? errorMessage;
  GallerySaverResult(this.success, this.errorMessage);
}

class GallerySaverUtil {
  static Future<GallerySaverResult> saveFile(String path, {bool isVideo = true}) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return GallerySaverResult(false, 'Local file not found.');
      }
      
      if (isVideo) {
        await Gal.putVideo(path);
      } else {
        await Gal.putImage(path);
      }
      return GallerySaverResult(true, null);
    } on GalException catch (e) {
      debugPrint('GalException: ${e.type}');
      // Map common Gal exceptions to user-friendly messages
      if (e.type == GalExceptionType.accessDenied) {
        return GallerySaverResult(false, 'Permission denied. Please grant access in settings.');
      }
      return GallerySaverResult(false, 'Save failed: ${e.type.name}');
    } catch (e) {
      debugPrint('General Gallery Error: $e');
      return GallerySaverResult(false, 'An unexpected error occurred.');
    }
  }
}
