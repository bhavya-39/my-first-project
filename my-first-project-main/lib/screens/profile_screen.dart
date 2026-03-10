import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/theme_provider.dart';
import '../services/expense_repository.dart';
import '../database/local_database.dart';
import '../widgets/profile_avatar.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _auth = FirebaseAuth.instance;
  final _authService = AuthService();
  final _themeProvider = ThemeProvider.instance;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  String _displayName = '';
  String _email = '';
  DateTime? _memberSince;
  PermissionStatus _smsPermission = PermissionStatus.denied;
  bool _notificationsEnabled = false;
  bool _loadingProfile = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _loadProfile();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check permissions when returning from device settings
      _checkPermissions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animController.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final firestoreProfile = await _authService.getUserProfile(user.uid);
    await _checkPermissions();

    if (mounted) {
      setState(() {
        _displayName = firestoreProfile?.name.isNotEmpty == true
            ? firestoreProfile!.name
            : (user.displayName?.isNotEmpty == true
                ? user.displayName!
                : _capitalize(user.email?.split('@').first ?? 'User'));
        _email = user.email ?? '';
        _memberSince =
            firestoreProfile?.createdAt ?? user.metadata.creationTime;
        _loadingProfile = false;
      });
      _animController.forward();
    }
  }

  Future<void> _checkPermissions() async {
    final smsStatus = await Permission.sms.status;
    final notifStatus = await Permission.notification.status;
    if (mounted) {
      setState(() {
        _smsPermission = smsStatus;
        _notificationsEnabled = notifStatus.isGranted;
      });
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String get _initial =>
      _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U';

  String _formatMemberSince(DateTime? dt) {
    if (dt == null) return 'Unknown';
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[dt.month]} ${dt.year}';
  }

  // ── Edit Profile (name + email) ──────────────────────────────────────────────

  Future<void> _showEditProfileSheet() async {
    final nameCtrl = TextEditingController(text: _displayName);
    final emailCtrl = TextEditingController(text: _email);
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    final isDark = _themeProvider.isDarkMode;
    final cardBg = isDark ? AppTheme.cardDark : Colors.white;
    final elevBg = isDark ? AppTheme.cardDarkElevated : Colors.grey.shade50;
    final textCol = isDark ? AppTheme.textDarkMode : AppTheme.textDark;
    final subCol = isDark ? AppTheme.textMediumDark : AppTheme.textMedium;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
        ),
        child: StatefulBuilder(
          builder: (ctx2, setSheetState) => Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: subCol.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Edit Profile',
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textCol)),
                const SizedBox(height: 4),
                Text('Update your profile photo, display name, and email',
                    style: GoogleFonts.poppins(fontSize: 12, color: subCol)),
                const SizedBox(height: 24),

                // Profile Photo
                Center(
                  child: Stack(
                    children: [
                      ProfileAvatar(
                        size: 80,
                        fallbackInitial: _initial,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.skyBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: cardBg, width: 2),
                          ),
                          child: const Icon(Icons.edit_rounded,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Name field
                TextFormField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: GoogleFonts.poppins(fontSize: 15, color: textCol),
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    labelStyle: GoogleFonts.poppins(color: subCol),
                    prefixIcon: Icon(Icons.person_outline_rounded,
                        color: AppTheme.skyBlue),
                    fillColor: elevBg,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Name cannot be empty';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Email field
                TextFormField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.poppins(fontSize: 15, color: textCol),
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: GoogleFonts.poppins(color: subCol),
                    prefixIcon:
                        Icon(Icons.email_outlined, color: AppTheme.skyBlue),
                    fillColor: elevBg,
                    helperText:
                        'A verification link will be sent to the new email',
                    helperStyle:
                        GoogleFonts.poppins(fontSize: 10, color: subCol),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email cannot be empty';
                    }
                    final emailRegex = RegExp(
                        r'^[\w\.\+\-]+@[\w\-]+\.[a-z]{2,}$',
                        caseSensitive: false);
                    if (!emailRegex.hasMatch(v.trim())) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheetState(() => saving = true);
                            try {
                              final user = _auth.currentUser!;
                              final newName = nameCtrl.text.trim();
                              final newEmail = emailCtrl.text.trim();

                              // Update display name
                              if (newName != _displayName) {
                                await user.updateDisplayName(newName);
                              }

                              // Update email via verification (safer)
                              if (newEmail != _email) {
                                await user.verifyBeforeUpdateEmail(newEmail);
                              }

                              if (mounted) {
                                setState(() {
                                  _displayName = newName;
                                  // Email shown only updates after verification
                                });
                                Navigator.pop(ctx);
                                _showSnack(
                                  newEmail != _email
                                      ? 'Name updated! Check $newEmail to verify your new address.'
                                      : 'Profile updated!',
                                  AppTheme.successGreen,
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                setSheetState(() => saving = false);
                                _showSnack('Update failed. Please try again.',
                                    AppTheme.errorRed);
                              }
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text('Save Changes',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Reset monthly data ────────────────────────────────────────────────────────

  Future<void> _handleResetMonthlyData() async {
    final isDark = _themeProvider.isDarkMode;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.cardDark : Colors.white,
        title: Text('Reset Monthly Data',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.textDarkMode : AppTheme.textDark)),
        content: Text(
            'This will delete all expense records for the current month. This action cannot be undone.',
            style: GoogleFonts.poppins(
                fontSize: 13,
                color: isDark ? AppTheme.textMediumDark : AppTheme.textMedium)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(
                      color: isDark
                          ? AppTheme.textMediumDark
                          : AppTheme.textMedium))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Reset',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final db = LocalDatabase.instance;
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      await db.deleteSavingsBetween(start, end);
      final dbInst = await db.database;
      await dbInst.delete('expenses',
          where: 'date >= ? AND date <= ?',
          whereArgs: [
            start.millisecondsSinceEpoch,
            end.millisecondsSinceEpoch
          ]);
      await ExpenseRepository.instance.refresh();
      if (mounted) {
        _showSnack('Monthly data reset successfully.', AppTheme.successGreen);
      }
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────────

  Future<void> _handleSignOut() async {
    final isDark = _themeProvider.isDarkMode;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sign Out',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.textDarkMode : AppTheme.textDark)),
        content: Text('Are you sure you want to sign out?',
            style: GoogleFonts.poppins(
                fontSize: 14,
                color: isDark ? AppTheme.textMediumDark : AppTheme.textMedium)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(
                      color: isDark
                          ? AppTheme.textMediumDark
                          : AppTheme.textMedium))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Sign Out',
                  style: GoogleFonts.poppins(
                      color: AppTheme.errorRed, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _authService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
    }
  }

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final cardBg = isDark ? AppTheme.cardDark : Colors.white;
    final textCol = isDark ? AppTheme.textDarkMode : AppTheme.textDark;
    final subCol = isDark ? AppTheme.textMediumDark : AppTheme.textMedium;
    final shadowCol = isDark
        ? Colors.black.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.06);

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: _loadingProfile
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.skyBlue))
                : FadeTransition(
                    opacity: _fadeAnim,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                      children: [
                        _buildProfileHeader(
                            isDark, cardBg, textCol, subCol, shadowCol),
                        const SizedBox(height: 16),
                        _buildEditButton(isDark),
                        const SizedBox(height: 24),
                        _buildSettingsCard(
                            isDark, cardBg, textCol, subCol, shadowCol),
                        const SizedBox(height: 20),
                        _buildLogoutButton(),
                        const SizedBox(height: 12),
                        Center(
                          child: Text('Student Money Manager v1.0.0',
                              style: GoogleFonts.poppins(
                                  fontSize: 10, color: subCol)),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── App bar ──────────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 24, 18),
          child: Row(
            children: [
              if (Navigator.canPop(context)) ...[
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 4),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Profile',
                      style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  Text('Manage your account',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.75))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Profile header ───────────────────────────────────────────────────────────

  Widget _buildProfileHeader(
      bool isDark, Color cardBg, Color textCol, Color subCol, Color shadowCol) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: shadowCol, blurRadius: 14, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          ProfileAvatar(
            size: 84,
            isLarge: true,
            fallbackInitial: _initial,
          ),
          const SizedBox(height: 14),
          Text(_displayName,
              style: GoogleFonts.poppins(
                  fontSize: 20, fontWeight: FontWeight.w700, color: textCol)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.email_outlined, size: 14, color: subCol),
              const SizedBox(width: 4),
              Text(_email,
                  style: GoogleFonts.poppins(fontSize: 13, color: subCol)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.skyBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: AppTheme.skyBlue.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 13, color: AppTheme.skyBlue),
                const SizedBox(width: 6),
                Text('Member since ${_formatMemberSince(_memberSince)}',
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.skyBlue)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Edit Profile button ──────────────────────────────────────────────────────

  Widget _buildEditButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _showEditProfileSheet,
        icon: const Icon(Icons.edit_rounded, size: 16),
        label: Text('Edit Profile',
            style:
                GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.skyBlue,
          side: const BorderSide(color: AppTheme.skyBlue, width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 13),
          backgroundColor:
              isDark ? AppTheme.skyBlue.withValues(alpha: 0.08) : null,
        ),
      ),
    );
  }

  // ── Settings card ────────────────────────────────────────────────────────────

  Widget _buildSettingsCard(
      bool isDark, Color cardBg, Color textCol, Color subCol, Color shadowCol) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: shadowCol, blurRadius: 14, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.skyBlueDark.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.settings_rounded,
                      color: AppTheme.skyBlueDark, size: 17),
                ),
                const SizedBox(width: 9),
                Text('App Settings',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textCol)),
              ],
            ),
          ),
          _divider(isDark),

          // Dark Mode toggle
          ListenableBuilder(
            listenable: _themeProvider,
            builder: (ctx, _) => _settingsTile(
              icon: _themeProvider.isDarkMode
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              iconColor: const Color(0xFF0EA5E9),
              title: 'Dark Mode',
              subtitle: _themeProvider.isDarkMode
                  ? 'Applies to all screens'
                  : 'Light mode active',
              textCol: textCol,
              subCol: subCol,
              isDark: isDark,
              trailing: Switch(
                value: _themeProvider.isDarkMode,
                onChanged: (_) => _themeProvider.toggle(),
              ),
              onTap: () => _themeProvider.toggle(),
            ),
          ),
          _divider(isDark),

          // Notifications
          _settingsTile(
            icon: Icons.notifications_outlined,
            iconColor: const Color(0xFFF59E0B),
            title: 'Notifications',
            subtitle: _notificationsEnabled ? 'Enabled' : 'Tap to enable',
            textCol: textCol,
            subCol: subCol,
            isDark: isDark,
            trailing:
                _statusBadge(_notificationsEnabled, 'Granted', 'Disabled'),
            onTap: () => openAppSettings(),
          ),
          _divider(isDark),

          // SMS Permission
          _settingsTile(
            icon: Icons.sms_outlined,
            iconColor: const Color(0xFF0EA5E9),
            title: 'SMS Permission',
            subtitle: 'Required for UPI auto-tracking',
            textCol: textCol,
            subCol: subCol,
            isDark: isDark,
            trailing: _statusBadge(
                _smsPermission.isGranted, 'Granted', 'Not Granted'),
            onTap: () async {
              if (_smsPermission.isGranted) {
                _showSnack(
                    'SMS permission already granted.', AppTheme.successGreen);
              } else {
                final status = await Permission.sms.request();
                setState(() => _smsPermission = status);
                if (status.isPermanentlyDenied) {
                  _showSnack(
                      'Permission permanently denied. Opening settings...',
                      AppTheme.errorRed);
                  openAppSettings();
                } else if (!status.isGranted) {
                  _showSnack('Permission is required for auto-tracking.',
                      AppTheme.errorRed);
                }
              }
            },
          ),
          _divider(isDark),

          // Reset Monthly Data
          _settingsTile(
            icon: Icons.refresh_rounded,
            iconColor: AppTheme.errorRed,
            title: 'Reset Monthly Data',
            subtitle: 'Clear all expenses for this month',
            textCol: textCol,
            subCol: subCol,
            isDark: isDark,
            trailing:
                Icon(Icons.chevron_right_rounded, color: subCol, size: 20),
            onTap: _handleResetMonthlyData,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _divider(bool isDark) => Divider(
        height: 1,
        indent: 18,
        endIndent: 18,
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.grey.shade100,
      );

  Widget _settingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color textCol,
    required Color subCol,
    required bool isDark,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textCol)),
                    Text(subtitle,
                        style:
                            GoogleFonts.poppins(fontSize: 11, color: subCol)),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(bool granted, String yes, String no) {
    final color = granted ? AppTheme.successGreen : AppTheme.textLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(granted ? yes : no,
          style: GoogleFonts.poppins(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  // ── Logout button ────────────────────────────────────────────────────────────

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _handleSignOut,
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: Text('Sign Out',
            style:
                GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.errorRed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
