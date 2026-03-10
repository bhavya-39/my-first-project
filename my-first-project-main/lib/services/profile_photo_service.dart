import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Singleton ChangeNotifier that manages the user's profile photo.
class ProfilePhotoService extends ChangeNotifier {
  ProfilePhotoService._();
  static final ProfilePhotoService instance = ProfilePhotoService._();

  static const _key = 'profilePhotoPath';

  String? _photoPath;
  String? get photoPath => _photoPath;

  final ImagePicker _picker = ImagePicker();

  /// Load saved photo path from disk on startup.
  Future<void> loadProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_key);

    if (path != null && File(path).existsSync()) {
      _photoPath = path;
      notifyListeners();
    }
  }

  /// Launch picker, cropper, and save to local directory.
  Future<bool> pickAndCropImage(ImageSource source) async {
    try {
      // 1. Pick Image
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
      );

      if (pickedFile == null) return false;

      // 2. Crop Image to Circle
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Avatar',
            toolbarColor: AppTheme.skyBlueDark,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            cropStyle: CropStyle.circle,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Crop Avatar',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            cropStyle: CropStyle.circle,
          ),
        ],
      );

      if (croppedFile == null) return false;

      // 3. Save to local app directory persistently
      final directory = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String newPath = '${directory.path}/avatar_$timestamp.png';

      final File newImage = await File(croppedFile.path).copy(newPath);

      // 4. Update state and save path to SharedPreferences
      _photoPath = newImage.path;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _photoPath!);

      return true;
    } catch (e) {
      debugPrint('Error picking or cropping image: \$e');
      return false;
    }
  }

  /// Remove the currently saved photo.
  Future<void> removePhoto() async {
    if (_photoPath == null) return;

    try {
      final file = File(_photoPath!);
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting old photo: \$e');
    }

    _photoPath = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
