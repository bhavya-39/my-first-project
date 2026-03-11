import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../services/profile_photo_service.dart';
import '../theme/app_theme.dart';

class ProfileAvatar extends StatefulWidget {
  final double size;
  final String fallbackInitial;
  final bool isLarge;
  final VoidCallback? onTap;

  const ProfileAvatar({
    super.key,
    required this.size,
    required this.fallbackInitial,
    this.isLarge = false,
    this.onTap,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  final _photoService = ProfilePhotoService.instance;

  @override
  void initState() {
    super.initState();
    _photoService.addListener(_onPhotoUpdate);
  }

  @override
  void dispose() {
    _photoService.removeListener(_onPhotoUpdate);
    super.dispose();
  }

  void _onPhotoUpdate() {
    if (mounted) setState(() {});
  }

  // ── Show Modal Sheet ────────────────────────────────────────────────────────
  Future<void> _showPhotoOptions() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.cardDark : Colors.white;
    final textCol = isDark ? AppTheme.textDarkMode : AppTheme.textDark;
    final subCol = isDark ? AppTheme.textMediumDark : AppTheme.textMedium;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: subCol.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Profile Photo',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textCol,
                ),
              ),
              const SizedBox(height: 16),

              // Camera option
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.skyBlueDark.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: AppTheme.skyBlueDark),
                ),
                title: Text('Take Photo',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, color: textCol)),
                onTap: () => _handleImagePick(ctx, ImageSource.camera),
              ),

              // Gallery option
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.skyBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      color: AppTheme.skyBlue),
                ),
                title: Text('Choose from Gallery',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, color: textCol)),
                onTap: () => _handleImagePick(ctx, ImageSource.gallery),
              ),

              // Remove option
              if (_photoService.photoPath != null)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: AppTheme.errorRed),
                  ),
                  title: Text('Remove Photo',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.errorRed)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _photoService.removePhoto();
                  },
                ),

              // Cancel option
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.grey),
                ),
                title: Text('Cancel',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, color: Colors.grey)),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleImagePick(BuildContext ctx, ImageSource source) async {
    Navigator.pop(ctx);
    await _photoService.pickAndCropImage(source);
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final path = _photoService.photoPath;
    final hasImage = path != null;

    final child = hasImage
        ? ClipOval(
            child: Image.file(
              File(path),
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
            ),
          )
        : Container(
            width: widget.size,
            height: widget.size,
            decoration: widget.isLarge
                ? BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.skyBlue, AppTheme.skyBlueDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  )
                : BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
            child: Center(
              child: Text(
                widget.fallbackInitial,
                style: GoogleFonts.poppins(
                  fontSize: widget.isLarge ? 34 : 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          );

    return GestureDetector(
      onTap: widget.onTap ?? _showPhotoOptions,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: widget.isLarge
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.5), width: 1.5),
          boxShadow: widget.isLarge
              ? [
                  BoxShadow(
                    color: AppTheme.skyBlue.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        // Add animated transition when photo updates
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget c, Animation<double> anim) {
            return FadeTransition(opacity: anim, child: c);
          },
          child: KeyedSubtree(
            key: ValueKey<bool>(hasImage),
            child: child,
          ),
        ),
      ),
    );
  }
}
