import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';

class ProfilePhotoCropper {
  const ProfilePhotoCropper._();

  static Future<XFile?> cropPickedPhoto(
    XFile photo, {
    String title = 'Ritaglia foto',
  }) async {
    final cropped = await _cropPath(photo.path, title: title);
    return cropped == null ? photo : XFile(cropped.path);
  }

  static Future<List<XFile>> cropPickedPhotos(
    Iterable<XFile> photos, {
    String titlePrefix = 'Ritaglia foto',
  }) async {
    final croppedPhotos = <XFile>[];
    var index = 1;
    for (final photo in photos) {
      final cropped = await cropPickedPhoto(
        photo,
        title: '$titlePrefix $index',
      );
      if (cropped != null) {
        croppedPhotos.add(cropped);
      }
      index += 1;
    }
    return croppedPhotos;
  }

  static Future<XFile?> cropExistingPhotoFromUrl(
    String imageUrl, {
    String title = 'Ritaglia foto',
  }) async {
    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Non riesco a scaricare la foto da ritagliare.');
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'approfittoffro_crop_',
    );
    final sourceFile = File(
      '${tempDir.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await sourceFile.writeAsBytes(response.bodyBytes, flush: true);

    final cropped = await _cropPath(sourceFile.path, title: title);
    return cropped == null ? null : XFile(cropped.path);
  }

  static Future<CroppedFile?> _cropPath(
    String sourcePath, {
    required String title,
  }) {
    return ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      maxWidth: 1800,
      maxHeight: 1800,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: title,
          toolbarColor: AppTheme.orange,
          toolbarWidgetColor: Colors.white,
          backgroundColor: AppTheme.cream,
          activeControlsWidgetColor: AppTheme.orange,
          cropFrameColor: AppTheme.orange,
          cropGridColor: AppTheme.orange.withValues(alpha: 0.75),
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          aspectRatioPresets: const [
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.original,
          ],
        ),
      ],
    );
  }
}
