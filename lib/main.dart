import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:unispace/core/constants/supabase_constants.dart';
import 'package:flutter_animate/flutter_animate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppPalette.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await Supabase.initialize(
    url: SupabaseConstants.supabaseUrl,
    anonKey: SupabaseConstants.supabaseAnonKey,
  );

  runApp(const UniSpaceApp());
}

class UniSpaceApp extends StatefulWidget {
  const UniSpaceApp({super.key});

  @override
  State<UniSpaceApp> createState() => _UniSpaceAppState();
}

class _UniSpaceAppState extends State<UniSpaceApp> {
  AuthSession? _session;
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _loadExistingSession();
  }

  String _nameFromEmail(String email, UniRole role) {
    final local = email
        .split('@')
        .first
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .trim();
    if (local.isEmpty) return role.defaultName;
    return local
        .split(RegExp(r'\s+'))
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Future<AuthSession> _sessionFromUser(User user) async {
    final email = user.email ?? '';
    final roleFromEmail = detectRoleFromEmail(email) ?? UniRole.student;
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) {
        final role =
            detectRoleFromName(profile['role']?.toString()) ?? roleFromEmail;
        return AuthSession(
          id: user.id,
          fullName:
              (profile['full_name']?.toString().trim().isNotEmpty ?? false)
              ? profile['full_name'].toString()
              : _nameFromEmail(email, role),
          email: profile['email']?.toString() ?? email,
          role: role,
        );
      }
    } catch (_) {
      // Fall back to email metadata if database profile is not ready yet.
    }
    final fullName = (user.userMetadata?['full_name'] as String?)?.trim();
    return AuthSession(
      id: user.id,
      fullName: fullName == null || fullName.isEmpty
          ? _nameFromEmail(email, roleFromEmail)
          : fullName,
      email: email,
      role: roleFromEmail,
    );
  }

  Future<void> _loadExistingSession() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null && user.email != null) {
      _session = await _sessionFromUser(user);
    }
    if (mounted) setState(() => _checkingSession = false);
  }

  Future<void> _completeAuth(User user) async {
    final session = await _sessionFromUser(user);
    if (mounted) setState(() => _session = session);
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniSpace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppPalette.bg,
        textTheme: GoogleFonts.dmSansTextTheme(
          ThemeData.dark().textTheme,
        ).apply(bodyColor: AppPalette.text, displayColor: AppPalette.text),
        colorScheme: const ColorScheme.dark(
          primary: AppPalette.accent,
          secondary: AppPalette.accent2,
          surface: AppPalette.surface,
          error: AppPalette.danger,
        ),
      ),
      home: _checkingSession
          ? const AuthLoadingScreen()
          : _session == null
          ? AuthScreen(onAuthenticated: _completeAuth)
          : UniSpaceDashboard(user: _session!, onSignOut: _signOut),
    );
  }
}

class AppPalette {
  AppPalette._();

  static const Color bg = Color(0xFF0A0D14);
  static const Color surface = Color(0xFF111520);
  static const Color surface2 = Color(0xFF161C2E);
  static const Color accent = Color(0xFF4F8EFF);
  static const Color accent2 = Color(0xFF7C5CFC);
  static const Color accent3 = Color(0xFF00D4AA);
  static const Color text = Color(0xFFEEF0F7);
  static const Color text2 = Color(0xFF8892B0);
  static const Color text3 = Color(0xFF4A5568);
  static const Color danger = Color(0xFFFF4F6A);
  static const Color warn = Color(0xFFF6A623);
  static const Color border = Color(0x12FFFFFF);

  static const LinearGradient mainGradient = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

enum UniRole { student, teacher, admin }

extension UniRoleX on UniRole {
  String get value => switch (this) {
    UniRole.student => 'student',
    UniRole.teacher => 'teacher',
    UniRole.admin => 'admin',
  };

  String get label => switch (this) {
    UniRole.student => 'Student',
    UniRole.teacher => 'Teacher',
    UniRole.admin => 'Admin',
  };

  String get emojiLabel => switch (this) {
    UniRole.student => '🎓 Student',
    UniRole.teacher => '👨‍🏫 Teacher',
    UniRole.admin => '🛠️ Admin',
  };

  String get defaultPage => switch (this) {
    UniRole.student => 'home',
    UniRole.teacher => 'teacher-dashboard',
    UniRole.admin => 'admin-dashboard',
  };

  String get defaultName => switch (this) {
    UniRole.student => 'Student User',
    UniRole.teacher => 'Teacher User',
    UniRole.admin => 'Admin User',
  };

  String get initials => switch (this) {
    UniRole.student => 'ST',
    UniRole.teacher => 'TR',
    UniRole.admin => 'AD',
  };
}

UniRole? detectRoleFromEmail(String email) {
  final normalized = email.toLowerCase().trim();
  if (normalized.endsWith('@student.lus.bd')) return UniRole.student;
  if (normalized.endsWith('@teacher.lus.bd')) return UniRole.teacher;
  if (normalized.endsWith('@admin.lus.bd')) return UniRole.admin;
  return null;
}

UniRole? detectRoleFromName(String? role) {
  switch ((role ?? '').toLowerCase().trim()) {
    case 'student':
      return UniRole.student;
    case 'teacher':
      return UniRole.teacher;
    case 'admin':
      return UniRole.admin;
    default:
      return null;
  }
}

class AuthSession {
  final String id;
  final String fullName;
  final String email;
  final UniRole role;

  const AuthSession({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
  });

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return role.initials;
    if (parts.length == 1)
      return parts.first
          .substring(0, math.min(parts.first.length, 2))
          .toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

enum AuthView { login, signup }

class AuthLoadingScreen extends StatelessWidget {
  const AuthLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppPalette.mainGradient,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text('🏛️', style: TextStyle(fontSize: 34)),
            ),
            const SizedBox(height: 18),
            Text(
              'UniSpace',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppPalette.text,
              ),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: AppPalette.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final Future<void> Function(User user) onAuthenticated;
  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  AuthView _view = AuthView.login;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSubmitting = false;
  UniRole? _detectedRole;

  bool get _isSignup => _view == AuthView.signup;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_updateDetectedRole);
  }

  @override
  void dispose() {
    _emailController.removeListener(_updateDetectedRole);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _updateDetectedRole() {
    final role = detectRoleFromEmail(_emailController.text.trim());
    if (role != _detectedRole) setState(() => _detectedRole = role);
  }

  String _nameFromEmail(String email, UniRole role) {
    final local = email
        .split('@')
        .first
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .trim();
    if (local.isEmpty) return role.defaultName;
    return local
        .split(RegExp(r'\s+'))
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Future<void> _ensureProfile(User user, String name, UniRole role) async {
    await Supabase.instance.client.from('profiles').upsert({
      'id': user.id,
      'email': user.email,
      'full_name': name,
      'role': role.value,
      'status': 'active',
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final role = detectRoleFromEmail(email);
    if (role == null) {
      _showAuthMessage(
        'Please use student.lus.bd, teacher.lus.bd, or admin.lus.bd email.',
      );
      return;
    }
    final name = _isSignup && _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : _nameFromEmail(email, role);

    setState(() => _isSubmitting = true);
    try {
      final AuthResponse response;
      if (_isSignup) {
        response = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': name, 'role': role.value},
        );
      } else {
        response = await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }

      final user = response.user ?? Supabase.instance.client.auth.currentUser;
      if (user == null) {
        _showAuthMessage(
          'Account created. Please confirm your email, then login.',
        );
        setState(() => _view = AuthView.login);
        return;
      }
      await _ensureProfile(user, name, role);
      await widget.onAuthenticated(user);
    } on AuthException catch (e) {
      _showAuthMessage(e.message);
    } catch (e) {
      _showAuthMessage(
        'Authentication failed. Check Supabase URL, anon key, and database setup.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _switchView(AuthView view) {
    setState(() {
      _view = view;
      _formKey.currentState?.reset();
      _confirmPasswordController.clear();
    });
  }

  void _showAuthMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppPalette.surface2,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.5, -0.55),
            radius: 1.45,
            colors: [Color(0xFF1A1040), AppPalette.bg],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _authLogo(),
                      const SizedBox(height: 32),
                      Text(
                        _isSignup ? 'Create Account' : 'Welcome Back',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isSignup
                            ? 'Sign up with your institutional email to access UniSpace.'
                            : 'Login to open your role-based UniSpace dashboard.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: AppPalette.text2,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _authCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _authLogo() {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppPalette.mainGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppPalette.accent.withOpacity(0.28),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Text('🏛️', style: TextStyle(fontSize: 36)),
        ),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (bounds) =>
              AppPalette.mainGradient.createShader(bounds),
          child: Text(
            'UniSpace',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _authCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppPalette.surface.withOpacity(0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppPalette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _authToggle(),
          const SizedBox(height: 22),
          if (_isSignup) ...[
            _inputField(
              controller: _nameController,
              label: 'Full Name',
              hint: 'e.g. Jakaria Hossain',
              icon: Icons.person_outline_rounded,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Please enter your full name'
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          _inputField(
            controller: _emailController,
            label: 'Institutional Email',
            hint: 'xyz@student.lus.bd',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty)
                return 'Please enter your email';
              if (!value.contains('@')) return 'Please enter a valid email';
              if (detectRoleFromEmail(value.trim()) == null)
                return 'Use student, teacher, or admin institutional email';
              return null;
            },
          ),
          if (_detectedRole != null) ...[
            const SizedBox(height: 10),
            Align(child: _roleBadge(_detectedRole!)),
          ],
          const SizedBox(height: 16),
          _inputField(
            controller: _passwordController,
            label: 'Password',
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            suffix: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppPalette.text2,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty)
                return 'Please enter your password';
              if (value.length < 6)
                return 'Password must be at least 6 characters';
              return null;
            },
          ),
          if (_isSignup) ...[
            const SizedBox(height: 16),
            _inputField(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureConfirmPassword,
              suffix: IconButton(
                onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppPalette.text2,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty)
                  return 'Please confirm your password';
                if (value != _passwordController.text)
                  return 'Passwords do not match';
                return null;
              },
            ),
          ],
          const SizedBox(height: 24),
          _authGradientButton(
            _isSubmitting
                ? 'Please wait…'
                : (_isSignup ? 'Create Account' : 'Login'),
            _isSubmitting ? null : _submit,
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _isSignup
                    ? 'Already have an account? '
                    : 'Don\'t have an account? ',
                style: GoogleFonts.dmSans(
                  color: AppPalette.text2,
                  fontSize: 13,
                ),
              ),
              GestureDetector(
                onTap: () =>
                    _switchView(_isSignup ? AuthView.login : AuthView.signup),
                child: Text(
                  _isSignup ? 'Login' : 'Sign Up',
                  style: GoogleFonts.dmSans(
                    color: AppPalette.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Allowed domains: student.lus.bd • teacher.lus.bd • admin.lus.bd',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              color: AppPalette.text3,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _authToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppPalette.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border),
      ),
      child: Row(
        children: [
          _toggleButton('Login', AuthView.login),
          _toggleButton('Sign Up', AuthView.signup),
        ],
      ),
    );
  }

  Widget _toggleButton(String label, AuthView view) {
    final active = _view == view;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchView(view),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? AppPalette.mainGradient : null,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              color: active ? Colors.white : AppPalette.text2,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: GoogleFonts.dmSans(color: AppPalette.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppPalette.text2, size: 21),
        suffixIcon: suffix,
        labelStyle: GoogleFonts.dmSans(
          color: AppPalette.text2,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: GoogleFonts.dmSans(color: AppPalette.text3, fontSize: 13),
        filled: true,
        fillColor: AppPalette.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.accent, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.danger),
        ),
      ),
    );
  }

  Widget _roleBadge(UniRole role) {
    final color = switch (role) {
      UniRole.student => AppPalette.accent,
      UniRole.teacher => AppPalette.accent3,
      UniRole.admin => AppPalette.accent2,
    };
    final icon = switch (role) {
      UniRole.student => Icons.school_outlined,
      UniRole.teacher => Icons.co_present_outlined,
      UniRole.admin => Icons.admin_panel_settings_outlined,
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            'Role detected: ${role.label}',
            style: GoogleFonts.dmSans(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _authGradientButton(String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: onTap == null ? 0.72 : 1,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppPalette.mainGradient,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: AppPalette.accent.withOpacity(0.25),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class NavEntry {
  final String id;
  final String icon;
  final IconData? iconData;
  final IconData? inactiveIconData;
  final String label;
  final String? badge;
  final Color? badgeColor;
  const NavEntry(
    this.id,
    this.icon,
    this.label, {
    this.iconData,
    this.inactiveIconData,
    this.badge,
    this.badgeColor,
  });
}

const Map<String, String> fixedTeacherSlots = {
  '08:00|09:00': '08:00 AM – 09:00 AM',
  '09:00|10:00': '09:00 AM – 10:00 AM',
  '10:00|11:00': '10:00 AM – 11:00 AM',
  '11:00|12:00': '11:00 AM – 12:00 PM',
  '12:00|13:00': '12:00 PM – 01:00 PM',
  '13:00|14:00': '01:00 PM – 02:00 PM',
  '14:00|15:00': '02:00 PM – 03:00 PM',
  '15:00|16:00': '03:00 PM – 04:00 PM',
};

class RoomInfo {
  final String id;
  final String name;
  final String icon;
  final String location;
  final String building;
  final int floor;
  final int capacity;
  final int available;
  final double rating;
  final List<String> tags;
  final List<Color> colors;
  final String status;

  const RoomInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.location,
    required this.building,
    required this.floor,
    required this.capacity,
    required this.available,
    required this.rating,
    required this.tags,
    required this.colors,
    required this.status,
  });

  factory RoomInfo.fromMap(Map<String, dynamic> row) {
    final building = row['building']?.toString() ?? 'Campus';
    final floor = _asInt(row['floor'], 1);
    final name = row['name']?.toString() ?? 'Study Room';
    final tags = _asStringList(row['facilities']);
    final status = row['status']?.toString() ?? 'available';
    return RoomInfo(
      id: row['id']?.toString() ?? '',
      name: name,
      icon: _iconForRoom(name, tags),
      building: building,
      floor: floor,
      location: '$building, Floor $floor',
      capacity: _asInt(row['total_seats'], 0),
      available: _asInt(row['available_seats'], 0),
      rating: _asDouble(row['rating'], 0),
      tags: tags.map((e) => _tagLabel(e)).toList(),
      colors: _colorsForRoom(name),
      status: status,
    );
  }

  bool get isFull => available <= 0 || status == 'fully_booked';
  bool get isPending => status == 'pending_approval' || status == 'unavailable';
  double get availablePercent =>
      capacity == 0 ? 0 : (available / capacity).clamp(0, 1).toDouble();
  String get displayStatus => isFull
      ? 'Full'
      : isPending
      ? 'Pending'
      : available < (capacity * .35)
      ? 'Busy'
      : 'Available';
}

class SlotAvailability {
  final String slotKey;
  final String timeSlot;
  final int totalSeats;
  final int bookedSeats;
  final int availableSeats;
  final String status;
  final String? teacherName;
  final String? teacherEmail;
  final String? teacherBookingId;

  const SlotAvailability({
    required this.slotKey,
    required this.timeSlot,
    required this.totalSeats,
    required this.bookedSeats,
    required this.availableSeats,
    required this.status,
    this.teacherName,
    this.teacherEmail,
    this.teacherBookingId,
  });

  factory SlotAvailability.fromMap(Map<String, dynamic> row) =>
      SlotAvailability(
        slotKey: row['slot_key']?.toString() ?? '',
        timeSlot: row['time_slot']?.toString() ?? '',
        totalSeats: _asInt(row['total_seats']),
        bookedSeats: _asInt(row['booked_seats']),
        availableSeats: _asInt(row['available_seats']),
        status:
            row['slot_status']?.toString() ??
            row['status']?.toString() ??
            'available',
        teacherName: row['teacher_name']?.toString(),
        teacherEmail: row['teacher_email']?.toString(),
        teacherBookingId: row['teacher_booking_id']?.toString(),
      );

  bool get isBlockedByAdmin =>
      status == 'blocked_by_admin' ||
      status == 'teacher_assigned' ||
      status == 'cancellation_pending';
  bool get isFullyBooked => status == 'fully_booked' || availableSeats <= 0;
  bool get studentSelectable =>
      !isBlockedByAdmin &&
      !isFullyBooked &&
      (status == 'available' || status == 'partially_booked');
  bool get adminSelectable => status == 'available';

  Color get statusColor {
    if (isBlockedByAdmin) return AppPalette.danger;
    if (status == 'cancellation_pending') return AppPalette.warn;
    if (isFullyBooked) return AppPalette.text3;
    if (status == 'partially_booked') return AppPalette.warn;
    return AppPalette.accent3;
  }

  String get statusLabel {
    switch (status) {
      case 'available':
        return 'Available';
      case 'partially_booked':
        return 'Partially Booked';
      case 'fully_booked':
        return 'Fully Booked';
      case 'blocked_by_admin':
      case 'teacher_assigned':
        return teacherName == null || teacherName!.trim().isEmpty
            ? 'Blocked by Teacher'
            : 'Blocked: $teacherName';
      case 'cancellation_pending':
        return teacherName == null || teacherName!.trim().isEmpty
            ? 'Teacher Cancellation Pending'
            : 'Pending: $teacherName';
      default:
        return status.replaceAll('_', ' ');
    }
  }
}

class BookingSlipInfo {
  final String bookingId;
  final String slipNumber;
  final String studentName;
  final String studentEmail;
  final String roomName;
  final String roomLocation;
  final String date;
  final String timeSlot;
  final String seatNumber;
  final String status;
  final String createdAt;

  const BookingSlipInfo({
    required this.bookingId,
    required this.slipNumber,
    required this.studentName,
    required this.studentEmail,
    required this.roomName,
    required this.roomLocation,
    required this.date,
    required this.timeSlot,
    required this.seatNumber,
    required this.status,
    required this.createdAt,
  });

  factory BookingSlipInfo.fromMap(Map<String, dynamic> row) {
    final id = row['booking_id']?.toString() ?? '';
    final fallbackSlip =
        'BK-${id.substring(0, math.min(8, id.length)).toUpperCase()}';
    return BookingSlipInfo(
      bookingId: id,
      slipNumber: row['slip_number']?.toString() ?? fallbackSlip,
      studentName: row['student_name']?.toString() ?? 'Student',
      studentEmail: row['student_email']?.toString() ?? '',
      roomName: row['room_name']?.toString() ?? 'Study Room',
      roomLocation: row['room_location']?.toString() ?? 'Campus',
      date: row['booking_date']?.toString() ?? '',
      timeSlot: row['time_slot']?.toString() ?? '',
      seatNumber: row['seat_number']?.toString() ?? '-',
      status: row['status']?.toString() ?? 'confirmed',
      createdAt: row['created_at']?.toString() ?? '',
    );
  }
}

class BookingInfo {
  final String id;
  final String roomId;
  final String roomName;
  final String roomLocation;
  final String roomBuilding;
  final List<String> facilities;
  final String userId;
  final String userName;
  final String teacherId;
  final String? bookedByAdminId;
  final String bookingType;
  final String date;
  final String startTime;
  final String endTime;
  final String timeSlot;
  final String status;
  final String purpose;
  final int seatsBooked;

  const BookingInfo({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.roomLocation,
    required this.roomBuilding,
    required this.facilities,
    required this.userId,
    required this.userName,
    required this.teacherId,
    required this.bookedByAdminId,
    required this.bookingType,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.timeSlot,
    required this.status,
    required this.purpose,
    required this.seatsBooked,
  });

  factory BookingInfo.fromMap(
    Map<String, dynamic> row, {
    Map<String, UserProfile> users = const {},
  }) {
    final room = row['rooms'] is Map
        ? Map<String, dynamic>.from(row['rooms'])
        : <String, dynamic>{};
    final bookingType =
        row['booking_type']?.toString() ?? 'student_seat_booking';
    final userId = row['user_id']?.toString() ?? '';
    final teacherId =
        row['teacher_id']?.toString() ??
        (bookingType == 'teacher_room_booking' ? userId : '');
    final profileId = teacherId.isNotEmpty ? teacherId : userId;
    final profile = users[profileId] ?? users[userId];
    final building = room['building']?.toString() ?? 'Campus';
    final floor = _asInt(room['floor'], 1);
    final start = _shortTime(row['start_time']?.toString() ?? '');
    final end = _shortTime(row['end_time']?.toString() ?? '');
    return BookingInfo(
      id: row['id']?.toString() ?? '',
      roomId: row['room_id']?.toString() ?? room['id']?.toString() ?? '',
      roomName:
          room['name']?.toString() ??
          row['room_name']?.toString() ??
          'Study Room',
      roomLocation: '$building, Floor $floor',
      roomBuilding: building,
      facilities: _asStringList(
        room['facilities'],
      ).map((e) => _tagLabel(e)).toList(),
      userId: profileId,
      userName:
          profile?.fullName ??
          row['user_name']?.toString() ??
          (bookingType == 'teacher_room_booking' ? 'Teacher' : 'User'),
      teacherId: teacherId,
      bookedByAdminId: row['booked_by_admin_id']?.toString(),
      bookingType: bookingType,
      date: row['date']?.toString() ?? '',
      startTime: start,
      endTime: end,
      timeSlot: (row['time_slot']?.toString().trim().isNotEmpty ?? false)
          ? row['time_slot'].toString()
          : '$start – $end',
      status:
          row['status']?.toString() ??
          (bookingType == 'teacher_room_booking' ? 'active' : 'confirmed'),
      purpose:
          row['purpose']?.toString() ??
          (bookingType == 'teacher_room_booking'
              ? 'Admin-assigned room booking'
              : 'Study'),
      seatsBooked: _asInt(row['seats_booked'], 1),
    );
  }

  bool get isTeacherRoomBooking => bookingType == 'teacher_room_booking';
  bool get canRequestTeacherCancellation =>
      isTeacherRoomBooking &&
      (status == 'active' || status == 'confirmed' || status == 'pending');
  String get displayDate => _dateDisplay(date);
  String get timeRange =>
      timeSlot.trim().isNotEmpty ? timeSlot : '$startTime – $endTime';
  String get facilitiesText =>
      facilities.isEmpty ? 'No facilities listed' : facilities.join(' • ');
}

class EventInfo {
  final String id;
  final String name;
  final String description;
  final String date;
  final String place;
  final String duration;
  final String guests;
  final DateTime createdAt;

  EventInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.date,
    required this.place,
    required this.duration,
    required this.guests,
    required this.createdAt,
  });

  factory EventInfo.fromMap(Map<String, dynamic> map) {
    return EventInfo(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      date: map['date']?.toString() ?? '',
      place: map['place']?.toString() ?? '',
      duration: map['duration']?.toString() ?? '',
      guests: map['guests']?.toString() ?? '',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'].toString()) : DateTime.now(),
    );
  }

  String get displayDate => _dateDisplay(date);
}


class StudyGroupInfo {
  final String id;
  final String name;
  final String description;
  final String? roomId;
  final String roomName;
  final String adminName;
  final String createdBy;
  final String date;
  final String startTime;
  final String endTime;
  final String timeSlot;
  final String status;
  final int memberCount;
  final int maxMembers;

  const StudyGroupInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.roomId,
    required this.roomName,
    required this.adminName,
    required this.createdBy,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.timeSlot,
    required this.status,
    required this.memberCount,
    required this.maxMembers,
  });

  factory StudyGroupInfo.fromMap(
    Map<String, dynamic> row, {
    Map<String, UserProfile> users = const {},
  }) {
    final room = row['rooms'] is Map
        ? Map<String, dynamic>.from(row['rooms'])
        : <String, dynamic>{};
    final createdBy = row['created_by']?.toString() ?? '';
    final start = row['start_time']?.toString() ?? '';
    final end = row['end_time']?.toString() ?? '';
    return StudyGroupInfo(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? 'Study Group',
      description: row['description']?.toString() ?? 'Group Study Session',
      roomId: row['room_id']?.toString(),
      roomName: room['name']?.toString() ?? 'No room selected',
      adminName: users[createdBy]?.fullName ?? 'Group Admin',
      createdBy: createdBy,
      date: row['date']?.toString() ?? '',
      startTime: _shortTime(start),
      endTime: _shortTime(end),
      timeSlot: (row['time_slot']?.toString().trim().isNotEmpty ?? false)
          ? row['time_slot'].toString()
          : '${_shortTime(start)} – ${_shortTime(end)}',
      status: row['status']?.toString() ?? 'active',
      memberCount: _asInt(row['member_count'], 0),
      maxMembers: _asInt(row['max_members'], 10),
    );
  }

  bool get isFull => memberCount >= maxMembers;
  String get displayDate => date.isEmpty ? 'No date' : _dateDisplay(date);
}

class GroupMemberInfo {
  final String id;
  final String groupId;
  final String userId;
  final String role;
  final String name;
  final String contact;
  final String batch;
  final String department;

  const GroupMemberInfo({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.role,
    required this.name,
    required this.contact,
    required this.batch,
    required this.department,
  });

  factory GroupMemberInfo.fromMap(
    Map<String, dynamic> row, {
    Map<String, UserProfile> users = const {},
  }) {
    final userId = row['user_id']?.toString() ?? '';
    return GroupMemberInfo(
      id: row['id']?.toString() ?? '',
      groupId: row['group_id']?.toString() ?? '',
      userId: userId,
      role: row['role']?.toString() ?? 'member',
      name: _firstNonEmpty([row['name'], users[userId]?.fullName, 'Student']),
      contact: _firstNonEmpty([row['contact_number'], 'Not provided']),
      batch: _firstNonEmpty([row['batch'], 'Not provided']),
      department: _firstNonEmpty([row['department'], 'Not provided']),
    );
  }

  bool get isAdmin => role == 'admin';
}

class GroupJoinRequestInfo {
  final String id;
  final String groupId;
  final String studentId;
  final String name;
  final String contact;
  final String batch;
  final String department;
  final String status;
  final DateTime requestedAt;

  const GroupJoinRequestInfo({
    required this.id,
    required this.groupId,
    required this.studentId,
    required this.name,
    required this.contact,
    required this.batch,
    required this.department,
    required this.status,
    required this.requestedAt,
  });

  factory GroupJoinRequestInfo.fromMap(Map<String, dynamic> row) =>
      GroupJoinRequestInfo(
        id: row['id']?.toString() ?? '',
        groupId: row['group_id']?.toString() ?? '',
        studentId: row['student_id']?.toString() ?? '',
        name: row['name']?.toString() ?? 'Student',
        contact: row['contact_number']?.toString() ?? 'Not provided',
        batch: row['batch']?.toString() ?? 'Not provided',
        department: row['department']?.toString() ?? 'Not provided',
        status: row['status']?.toString() ?? 'pending',
        requestedAt:
            DateTime.tryParse(row['requested_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> row) => AppNotification(
    id: row['id']?.toString() ?? '',
    title: row['title']?.toString() ?? 'Notification',
    body: row['body']?.toString() ?? '',
    type: row['type']?.toString() ?? 'system',
    isRead: row['is_read'] == true,
    createdAt:
        DateTime.tryParse(row['created_at']?.toString() ?? '') ??
        DateTime.now(),
  );
}

class UserProfile {
  final String id;
  final String fullName;
  final String email;
  final UniRole role;
  final String status;

  const UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.status,
  });

  factory UserProfile.fromMap(Map<String, dynamic> row) => UserProfile(
    id: row['id']?.toString() ?? '',
    fullName: row['full_name']?.toString() ?? 'User',
    email: row['email']?.toString() ?? '',
    role: detectRoleFromName(row['role']?.toString()) ?? UniRole.student,
    status: row['status']?.toString() ?? 'active',
  );

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return role.initials;
    if (parts.length == 1)
      return parts.first
          .substring(0, math.min(2, parts.first.length))
          .toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class RoomRequestInfo {
  final String id;
  final String roomId;
  final String roomName;
  final String requestedBy;
  final String requesterName;
  final String reason;
  final String status;
  final String createdAt;
  final String? bookingId;
  final String bookingDate;
  final String timeSlot;

  const RoomRequestInfo({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.requestedBy,
    required this.requesterName,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.bookingId,
    required this.bookingDate,
    required this.timeSlot,
  });

  factory RoomRequestInfo.fromMap(
    Map<String, dynamic> row, {
    Map<String, UserProfile> users = const {},
  }) {
    final room = row['rooms'] is Map
        ? Map<String, dynamic>.from(row['rooms'])
        : <String, dynamic>{};
    final booking = row['bookings'] is Map
        ? Map<String, dynamic>.from(row['bookings'])
        : <String, dynamic>{};
    final requestedBy =
        row['requested_by']?.toString() ?? row['teacher_id']?.toString() ?? '';
    final start = _shortTime(booking['start_time']?.toString() ?? '');
    final end = _shortTime(booking['end_time']?.toString() ?? '');
    return RoomRequestInfo(
      id: row['id']?.toString() ?? '',
      roomId: row['room_id']?.toString() ?? '',
      roomName: room['name']?.toString() ?? 'Study Room',
      requestedBy: requestedBy,
      requesterName: users[requestedBy]?.fullName ?? 'Teacher',
      reason: row['reason']?.toString() ?? 'Cancellation requested',
      status: row['status']?.toString() ?? 'pending',
      createdAt: _dateDisplay(row['created_at']?.toString() ?? ''),
      bookingId: row['booking_id']?.toString(),
      bookingDate: _dateDisplay(booking['date']?.toString() ?? ''),
      timeSlot: (booking['time_slot']?.toString().trim().isNotEmpty ?? false)
          ? booking['time_slot'].toString()
          : '$start – $end',
    );
  }
}

class UniSpaceRepository {
  final SupabaseClient client;
  UniSpaceRepository(this.client);

  String get currentUserId => client.auth.currentUser!.id;

  Future<List<RoomInfo>> fetchRooms() async {
    final rows = await client.from('rooms').select().order('name');
    return (rows as List)
        .map((e) => RoomInfo.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<UserProfile>> fetchUsers() async {
    final rows = await client.from('profiles').select().order('full_name');
    return (rows as List)
        .map((e) => UserProfile.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<BookingInfo>> fetchBookings(
    UniRole role,
    Map<String, UserProfile> users,
  ) async {
    dynamic query = client.from('bookings').select('*, rooms(*)');
    if (role == UniRole.student || role == UniRole.teacher)
      query = query.eq('user_id', currentUserId);
    final rows = await query
        .order('date', ascending: false)
        .order('start_time', ascending: false);
    return (rows as List)
        .map(
          (e) =>
              BookingInfo.fromMap(Map<String, dynamic>.from(e), users: users),
        )
        .toList();
  }

  Future<List<StudyGroupInfo>> fetchGroups(
    Map<String, UserProfile> users,
  ) async {
    final rows = await client
        .from('study_groups')
        .select('*, rooms(*)')
        .eq('status', 'active')
        .order('created_at', ascending: false);
    return (rows as List)
        .map(
          (e) => StudyGroupInfo.fromMap(
            Map<String, dynamic>.from(e),
            users: users,
          ),
        )
        .toList();
  }

  Future<List<GroupMemberInfo>> fetchGroupMembers(
    String groupId,
    Map<String, UserProfile> users,
  ) async {
    final rows = await client
        .from('group_members')
        .select()
        .eq('group_id', groupId)
        .order('joined_at');
    return (rows as List)
        .map(
          (e) => GroupMemberInfo.fromMap(
            Map<String, dynamic>.from(e),
            users: users,
          ),
        )
        .toList();
  }

  Future<List<GroupJoinRequestInfo>> fetchGroupJoinRequests(
    String groupId,
  ) async {
    final rows = await client
        .from('group_join_requests')
        .select()
        .eq('group_id', groupId)
        .order('requested_at', ascending: false);
    return (rows as List)
        .map((e) => GroupJoinRequestInfo.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<String> groupUserStatus(String groupId) async {
    final member = await client
        .from('group_members')
        .select('role')
        .eq('group_id', groupId)
        .eq('user_id', currentUserId)
        .maybeSingle();
    if (member != null)
      return member['role']?.toString() == 'admin' ? 'admin' : 'member';

    final pending = await client
        .from('group_join_requests')
        .select('id')
        .eq('group_id', groupId)
        .eq('student_id', currentUserId)
        .eq('status', 'pending')
        .maybeSingle();
    return pending == null ? 'none' : 'pending';
  }

  Future<List<AppNotification>> fetchNotifications() async {
    final rows = await client
        .from('notifications')
        .select()
        .eq('user_id', currentUserId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => AppNotification.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<RoomRequestInfo>> fetchRequests(
    UniRole role,
    Map<String, UserProfile> users,
  ) async {
    dynamic query = client
        .from('room_requests')
        .select('*, rooms(*), bookings(*)');
    if (role == UniRole.teacher)
      query = query.eq('requested_by', currentUserId);
    final rows = await query.order('created_at', ascending: false);
    return (rows as List)
        .map(
          (e) => RoomRequestInfo.fromMap(
            Map<String, dynamic>.from(e),
            users: users,
          ),
        )
        .toList();
  }

  Future<List<SlotAvailability>> fetchSlotAvailability({
    required String roomId,
    required DateTime date,
  }) async {
    final rows = await client.rpc(
      'get_room_slot_availability',
      params: {'p_room_id': roomId, 'p_date': _isoDate(date)},
    );
    return (rows as List)
        .map((e) => SlotAvailability.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<BookingSlipInfo> fetchBookingSlip(String bookingId) async {
    final row = await client.rpc(
      'get_booking_slip',
      params: {'p_booking_id': bookingId},
    );
    return BookingSlipInfo.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<BookingSlipInfo> bookSeat({
    required String roomId,
    required DateTime date,
    required String startTime,
    required String endTime,
    required String purpose,
  }) async {
    final bookingId = await client.rpc(
      'book_seat',
      params: {
        'p_room_id': roomId,
        'p_date': _isoDate(date),
        'p_start': startTime,
        'p_end': endTime,
        'p_purpose': purpose,
      },
    );
    return fetchBookingSlip(bookingId.toString());
  }

  Future<void> cancelBooking(String bookingId) async {
    await client.rpc('cancel_booking', params: {'p_booking_id': bookingId});
  }

  Future<void> createGroup({
    required String name,
    required String description,
    required String? roomId,
    required DateTime date,
    required String startTime,
    required String endTime,
    required int maxMembers,
  }) async {
    await client.rpc(
      'create_study_group_with_admin',
      params: {
        'p_name': name,
        'p_description': description,
        'p_date': _isoDate(date),
        'p_start_time': startTime,
        'p_end_time': endTime,
        'p_max_members': maxMembers,
        'p_room_id': roomId,
      },
    );
  }

  Future<void> updateGroup({
    required String groupId,
    required String name,
    required String description,
    required String? roomId,
    required DateTime date,
    required String startTime,
    required String endTime,
    required int maxMembers,
  }) async {
    await client.rpc(
      'update_study_group_details',
      params: {
        'p_group_id': groupId,
        'p_name': name,
        'p_description': description,
        'p_date': _isoDate(date),
        'p_start_time': startTime,
        'p_end_time': endTime,
        'p_max_members': maxMembers,
        'p_room_id': roomId,
      },
    );
  }

  Future<void> deleteGroup(String groupId) async {
    await client.rpc(
      'cancel_study_group_by_admin',
      params: {'p_group_id': groupId},
    );
  }

  Future<void> requestToJoinGroup({
    required String groupId,
    required String name,
    required String contact,
    required String batch,
    required String department,
  }) async {
    await client.rpc(
      'request_to_join_group',
      params: {
        'p_group_id': groupId,
        'p_name': name,
        'p_contact_number': contact,
        'p_batch': batch,
        'p_department': department,
      },
    );
  }

  Future<void> approveGroupRequest(String requestId) async {
    await client.rpc(
      'approve_group_join_request',
      params: {'p_request_id': requestId},
    );
  }

  Future<void> rejectGroupRequest(String requestId) async {
    await client.rpc(
      'reject_group_join_request',
      params: {'p_request_id': requestId},
    );
  }

  Future<void> removeGroupMember({
    required String groupId,
    required String memberUserId,
  }) async {
    await client.rpc(
      'remove_group_member',
      params: {'p_group_id': groupId, 'p_member_id': memberUserId},
    );
  }

  Future<void> submitCancellationRequest(
    String bookingId,
    String reason,
  ) async {
    await client.rpc(
      'teacher_cancel_request',
      params: {'p_booking_id': bookingId, 'p_reason': reason},
    );
  }

  Future<void> decideRequest(String requestId, bool approved) async {
    await client.rpc(
      'admin_decide_request',
      params: {'p_request_id': requestId, 'p_approved': approved},
    );
  }

  Future<String> addRoom({
    required String name,
    required String building,
    required int floor,
    required int totalSeats,
    required List<String> facilities,
  }) async {
    final row = await client
        .from('rooms')
        .insert({
          'name': name,
          'building': building,
          'floor': floor,
          'total_seats': totalSeats,
          'available_seats': totalSeats,
          'facilities': facilities,
          'status': 'available',
          'rating': 0,
        })
        .select('id')
        .single();
    return row['id'].toString();
  }

  Future<void> assignTeacherRoom({
    required String roomId,
    required String teacherId,
    required DateTime date,
    required List<String> slots,
  }) async {
    if (slots.isEmpty) throw Exception('Select at least one time slot.');
    await client.rpc(
      'admin_assign_teacher_room',
      params: {
        'p_room_id': roomId,
        'p_teacher_id': teacherId,
        'p_date': _isoDate(date),
        'p_slots': slots,
      },
    );
  }

  Future<void> updateRoom(
    RoomInfo room, {
    String? name,
    String? building,
    int? floor,
    int? totalSeats,
    List<String>? facilities,
    String? status,
  }) async {
    final newTotal = totalSeats ?? room.capacity;
    final delta = newTotal - room.capacity;
    final newAvailable = math.max(0, room.available + delta);
    await client
        .from('rooms')
        .update({
          if (name != null) 'name': name,
          if (building != null) 'building': building,
          if (floor != null) 'floor': floor,
          if (totalSeats != null) 'total_seats': totalSeats,
          if (totalSeats != null) 'available_seats': newAvailable,
          if (facilities != null) 'facilities': facilities,
          if (status != null) 'status': status,
        })
        .eq('id', room.id);
  }

  Future<void> deleteRoom(String roomId) async {
    // Step 1: Delete room_requests (references both rooms AND bookings — no CASCADE)
    try {
      await client.from('room_requests').delete().eq('room_id', roomId);
    } catch (_) {}

    // Step 2: Delete bookings (has CASCADE but also have booking_slips as children)
    // First delete booking_slips that reference these bookings
    try {
      final bookingIds = await client
          .from('bookings')
          .select('id')
          .eq('room_id', roomId);
      for (final b in bookingIds) {
        try {
          await client.from('booking_slips').delete().eq('booking_id', b['id']);
        } catch (_) {}
      }
    } catch (_) {}
    try {
      await client.from('bookings').delete().eq('room_id', roomId);
    } catch (_) {}

    // Step 3: Nullify study_groups.room_id (no CASCADE — set to null to unlink)
    try {
      await client
          .from('study_groups')
          .update({'room_id': null}).eq('room_id', roomId);
    } catch (_) {}

    // Step 4: Delete the room (room_ratings CASCADE auto-deletes)
    await client.from('rooms').delete().eq('id', roomId);
  }

  Future<void> updateUserRoleStatus(
    String userId,
    UniRole role,
    String status,
  ) async {
    await client
        .from('profiles')
        .update({'role': role.value, 'status': status})
        .eq('id', userId);
  }

  Future<void> deleteUser(String userId) async {
    // Delete user's bookings first, then profile
    await client.from('bookings').delete().eq('user_id', userId);
    await client.from('notifications').delete().eq('user_id', userId);
    await client.from('profiles').delete().eq('id', userId);
  }

  Future<void> markNotificationRead(String id) async {
    await client.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<List<EventInfo>> fetchEvents() async {
    final rows = await client.from('events').select().order('date', ascending: true);
    return (rows as List)
        .map((e) => EventInfo.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> addEvent({
    required String name,
    required String description,
    required DateTime date,
    required String place,
    required String duration,
    required String guests,
  }) async {
    await client.from('events').insert({
      'name': name,
      'description': description,
      'date': _isoDate(date),
      'place': place,
      'duration': duration,
      'guests': guests,
    });
  }

  Future<void> updateEvent({
    required String id,
    required String name,
    required String description,
    required DateTime date,
    required String place,
    required String duration,
    required String guests,
  }) async {
    await client.from('events').update({
      'name': name,
      'description': description,
      'date': _isoDate(date),
      'place': place,
      'duration': duration,
      'guests': guests,
    }).eq('id', id);
  }

  Future<void> deleteEvent(String id) async {
    await client.from('events').delete().eq('id', id);
  }
}

class UniSpaceDashboard extends StatefulWidget {
  final AuthSession user;
  final VoidCallback onSignOut;
  const UniSpaceDashboard({
    super.key,
    required this.user,
    required this.onSignOut,
  });

  @override
  State<UniSpaceDashboard> createState() => _UniSpaceDashboardState();
}

class _UniSpaceDashboardState extends State<UniSpaceDashboard> {
  late final UniSpaceRepository _repo;
  late final UniRole _role;
  late String _page;
  RealtimeChannel? _channel;
  Timer? _toastTimer;
  String? _toastMessage;
  bool _toastVisible = false;
  bool _loading = true;
  String? _error;
  String _activeRoomFilter = 'All Rooms';
  String _activeBookingFilter = 'All';
  String _adminTeacherFilter = 'all';
  String _adminRoomFilter = 'all';
  String _adminSlotFilter = 'all';
  DateTime? _adminDateFilter;

  // Teacher filter variables
  DateTime? _teacherDateFilter;
  String _teacherBuildingFilter = 'All';
  String _teacherStatusFilter = 'All';

  List<RoomInfo> _rooms = [];
  List<BookingInfo> _bookings = [];
  List<StudyGroupInfo> _groups = [];
  List<AppNotification> _notifications = [];
  List<UserProfile> _users = [];
  List<RoomRequestInfo> _requests = [];
  List<SlotAvailability> _todaySlots = [];
  List<EventInfo> _events = [];

  Map<String, UserProfile> get _userMap => {for (final u in _users) u.id: u};
  int get _unreadCount => _notifications.where((n) => !n.isRead).length;
  List<RoomRequestInfo> get _pendingRequests =>
      _requests.where((r) => r.status == 'pending').toList();
  List<BookingInfo> get _activeBookings => _bookings
      .where(
        (b) => [
          'confirmed',
          'pending',
          'active',
          'cancellation_pending',
        ].contains(b.status),
      )
      .toList();
  List<UserProfile> get _teachers => _users
      .where((u) => u.role == UniRole.teacher && u.status == 'active')
      .toList();

  @override
  void initState() {
    super.initState();
    _repo = UniSpaceRepository(Supabase.instance.client);
    _role = widget.user.role;
    _page = _role.defaultPage;
    _loadAll();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    final client = Supabase.instance.client;
    _channel = client.channel('unispace-live-${widget.user.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rooms',
        callback: (_) => _loadAll(silent: true),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'bookings',
        callback: (_) => _loadAll(silent: true),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        callback: (_) => _loadAll(silent: true),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'study_groups',
        callback: (_) => _loadAll(silent: true),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'group_members',
        callback: (_) => _loadAll(silent: true),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'group_join_requests',
        callback: (_) => _loadAll(silent: true),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'room_requests',
        callback: (_) => _loadAll(silent: true),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'booking_slips',
        callback: (_) => _loadAll(silent: true),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'profiles',
        callback: (_) => _loadAll(silent: true),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'events',
        callback: (_) => _loadAll(silent: true),
      )
      ..subscribe();
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!silent && mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final users = await _repo.fetchUsers();
      final userMap = {for (final u in users) u.id: u};
      final rooms = await _repo.fetchRooms();
      final bookings = await _repo.fetchBookings(_role, userMap);
      final groups = _role == UniRole.student
          ? await _repo.fetchGroups(userMap)
          : <StudyGroupInfo>[];
      final notifications = await _repo.fetchNotifications();
      final requests = _role == UniRole.teacher || _role == UniRole.admin
          ? await _repo.fetchRequests(_role, userMap)
          : <RoomRequestInfo>[];
      final events = await _repo.fetchEvents();
      final List<SlotAvailability> todaySlots;
      if (rooms.isNotEmpty) {
        final todaySlotsList = await Future.wait(
          rooms.map((r) => _repo.fetchSlotAvailability(roomId: r.id, date: DateTime.now()))
        );
        todaySlots = todaySlotsList.expand((s) => s).toList();
      } else {
        todaySlots = [];
      }

      if (!mounted) return;
      setState(() {
        _users = users;
        _rooms = rooms;
        _bookings = bookings;
        _groups = groups;
        _notifications = notifications;
        _requests = requests;
        _events = events;
        _todaySlots = todaySlots;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _navigate(String page) => setState(() => _page = page);

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastVisible = true;
    });
    _toastTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _toastVisible = false);
    });
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      await _loadAll(silent: true);
      _showToast(success);
    } catch (e) {
      _showToast('⚠️ ${_friendlyError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final showHeader = (_role == UniRole.student && _page == 'home') ||
            (_role == UniRole.teacher && _page == 'teacher-dashboard') ||
            (_role == UniRole.admin && _page == 'admin-dashboard');
        return Scaffold(
          body: Stack(
            children: [
              Column(
                children: [
                  if (showHeader) _topBar(isDesktop: isDesktop),
                  Expanded(
                    child: SafeArea(
                      top: !showHeader,
                      bottom: false,
                      child: RefreshIndicator(
                        onRefresh: () => _loadAll(),
                        color: AppPalette.accent,
                        backgroundColor: AppPalette.surface,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: SingleChildScrollView(
                            key: ValueKey(
                              '$_page-$_loading-${_rooms.length}-${_bookings.length}-${_requests.length}',
                            ),
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              isDesktop ? 28 : 18,
                              isDesktop ? 28 : 18,
                              isDesktop ? 28 : 18,
                              isDesktop ? 28 : 18,
                            ),
                            child: _loading ? _loadingView() : _pageBody(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(right: 24, bottom: 24, child: _toastOverlay()),
            ],
          ),
          bottomNavigationBar: _bottomNavFooter(isDesktop: isDesktop),
        );
      },
    );
  }

  Widget _toastOverlay() {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 260),
      offset: _toastVisible ? Offset.zero : const Offset(0, 0.3),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 260),
        opacity: _toastVisible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !_toastVisible,
          child: _toastMessage == null
              ? const SizedBox.shrink()
              : _toast(_toastMessage!),
        ),
      ),
    );
  }

  List<NavEntry> _navItems(UniRole role) {
    switch (role) {
      case UniRole.student:
        return [
          const NavEntry('home', '🏠', 'Home', iconData: Icons.home_rounded, inactiveIconData: Icons.home_outlined),
          const NavEntry('rooms', '🚪', 'Browse Rooms', iconData: Icons.meeting_room_rounded, inactiveIconData: Icons.meeting_room_outlined),
          const NavEntry('bookings', '📅', 'My Bookings', iconData: Icons.calendar_month_rounded, inactiveIconData: Icons.calendar_month_outlined),
          const NavEntry('groups', '👥', 'Group Study', iconData: Icons.groups_rounded, inactiveIconData: Icons.groups_outlined),
          const NavEntry('student-events', '📅', 'Events', iconData: Icons.event_rounded, inactiveIconData: Icons.event_outlined),
        ];
      case UniRole.teacher:
        return [
          const NavEntry('teacher-dashboard', '📊', 'Dashboard', iconData: Icons.dashboard_rounded, inactiveIconData: Icons.dashboard_outlined),
          const NavEntry('teacher-assigned-rooms', '🏫', 'Assigned Rooms', iconData: Icons.meeting_room_rounded, inactiveIconData: Icons.meeting_room_outlined),
          const NavEntry('teacher-events', '📅', 'Events', iconData: Icons.event_rounded, inactiveIconData: Icons.event_outlined),
        ];
      case UniRole.admin:
        return [
          const NavEntry('admin-dashboard', '📊', 'Dashboard', iconData: Icons.dashboard_rounded, inactiveIconData: Icons.dashboard_outlined),
          const NavEntry('admin-users', '👥', 'User Management', iconData: Icons.people_rounded, inactiveIconData: Icons.people_outline_rounded),
          const NavEntry('admin-rooms', '🚪', 'Room Management', iconData: Icons.meeting_room_rounded, inactiveIconData: Icons.meeting_room_outlined),
          NavEntry(
            'admin-approval',
            '✅',
            'Approval Panel',
            iconData: Icons.fact_check_rounded,
            inactiveIconData: Icons.fact_check_outlined,
            badge: _pendingRequests.isNotEmpty
                ? _pendingRequests.length.toString()
                : null,
          ),
          const NavEntry('admin-events', '📅', 'Events', iconData: Icons.event_rounded, inactiveIconData: Icons.event_outlined),
          const NavEntry('admin-monitor', '📡', 'Booking Monitor', iconData: Icons.monitor_heart_rounded, inactiveIconData: Icons.monitor_heart_outlined),
        ];
    }
  }

  Widget _bottomNavFooter({required bool isDesktop}) {
    final navItems = _navItems(_role);
    return SafeArea(
      top: false,
      child: Container(
        height: isDesktop ? 78 : 82,
        decoration: BoxDecoration(
          color: AppPalette.surface,
          border: const Border(top: BorderSide(color: AppPalette.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 28 : 4,
          vertical: isDesktop ? 10 : 8,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: navItems
              .map((item) => _bottomNavTile(item, isDesktop: isDesktop))
              .toList(),
        ),
      ),
    );
  }

  Widget _bottomNavTile(NavEntry item, {required bool isDesktop}) {
    final active = _page == item.id;
    final labelSize = isDesktop
        ? 12.0
        : (_navItems(_role).length >= 6 ? 9.0 : 10.0);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _navigate(item.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: EdgeInsets.symmetric(horizontal: isDesktop ? 4 : 2),
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 8 : 3,
            vertical: active ? 7 : 6,
          ),
          decoration: BoxDecoration(
            color: active
                ? AppPalette.accent.withOpacity(0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active
                  ? AppPalette.accent.withOpacity(0.35)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  item.iconData != null
                      ? Icon(
                          active
                              ? item.iconData
                              : (item.inactiveIconData ?? item.iconData),
                          size: isDesktop ? 22 : 20,
                          color: active ? AppPalette.accent : AppPalette.text2,
                        )
                      : Text(
                          item.icon,
                          style: TextStyle(fontSize: isDesktop ? 19 : 17),
                        ),
                  if (item.badge != null)
                    Positioned(
                      right: -10,
                      top: -7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: item.badgeColor ?? AppPalette.danger,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppPalette.surface,
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          item.badge!,
                          style: _body(
                            size: 8.5,
                            color: Colors.white,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _body(
                  size: labelSize,
                  height: 1.05,
                  color: active ? AppPalette.accent : AppPalette.text2,
                  weight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar({required bool isDesktop}) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 28 : 14),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        border: Border(bottom: BorderSide(color: AppPalette.border)),
      ),
      child: Row(
        children: [
          _logoHeader(),
          const Spacer(),
          if (isDesktop) ...[_searchBar(), const SizedBox(width: 10)],
          _topIcon(
            '🔔',
            showDot: _unreadCount > 0,
            onTap: () => _navigate('notifications'),
          ),
          const SizedBox(width: 10),
          _topIcon('↻', onTap: () => _loadAll()),
          const SizedBox(width: 10),
          _profileMenuButton(),
        ],
      ),
    );
  }

  Widget _logoHeader() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: AppPalette.mainGradient,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('🏛️', style: TextStyle(fontSize: 18)),
      ),
      const SizedBox(width: 10),
      _gradientText('UniSpace', size: 22, weight: FontWeight.w800),
    ],
  );

  Widget _profileMenuButton() {
    return PopupMenuButton<String>(
      tooltip: 'Profile',
      color: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      offset: const Offset(0, 46),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppPalette.border),
      ),
      onSelected: (value) {
        if (value == 'profile') _navigate('profile');
        if (value == 'logout') widget.onSignOut();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Row(
            children: [
              _avatar(widget.user.initials, size: 34, radius: 9),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.user.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _body(size: 13, weight: FontWeight.w800),
                    ),
                    Text(
                      widget.user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _body(size: 11, color: AppPalette.text2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.user.role.emojiLabel,
                      style: _body(
                        size: 11,
                        color: AppPalette.accent3,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'profile',
          child: Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                color: AppPalette.accent,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                'Open Profile',
                style: _body(size: 13, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              const Icon(
                Icons.logout_rounded,
                color: AppPalette.danger,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                'Log Out',
                style: _body(
                  size: 13,
                  color: AppPalette.danger,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.border),
        ),
        child: _avatar(widget.user.initials, size: 30, radius: 7),
      ),
    );
  }

  Widget _searchBar() => Container(
    width: 260,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: AppPalette.surface2,
      border: Border.all(color: AppPalette.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Text('🔍', style: _body(size: 13, color: AppPalette.text3)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Search rooms, groups…',
            overflow: TextOverflow.ellipsis,
            style: _body(size: 13, color: AppPalette.text3),
          ),
        ),
      ],
    ),
  );

  Widget _loadingView() => SizedBox(
    height: 420,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppPalette.accent),
          const SizedBox(height: 16),
          Text(
            'Loading live UniSpace data…',
            style: _body(color: AppPalette.text2),
          ),
        ],
      ),
    ),
  );

  Widget _pageBody() {
    if (_error != null) return _errorPanel();
    switch (_page) {
      case 'home':
        return _studentHome();
      case 'rooms':
        return _roomsPage();
      case 'bookings':
        return _myBookingsPage();
      case 'groups':
        return _groupsPage();
      case 'student-events':
        return _studentEventsPage();
      case 'notifications':
        return _notificationsPage();
      case 'profile':
        return _profilePage();
      case 'teacher-dashboard':
        return _teacherDashboard();
      case 'teacher-assigned-rooms':
        return _teacherAssignedRoomsPage();
      case 'teacher-events':
        return _teacherEventsPage();
      case 'teacher-bookings':
        return _teacherBookings();
      case 'teacher-cancel':
        return _teacherCancelRequests();
      case 'admin-dashboard':
        return _adminDashboard();
      case 'admin-users':
        return _adminUsers();
      case 'admin-rooms':
        return _adminRooms();
      case 'admin-approval':
        return _adminApproval();
      case 'admin-events':
        return _adminEventsPage();
      case 'admin-monitor':
        return _adminMonitor();
      default:
        return _studentHome();
    }
  }

  Widget _errorPanel() {
    return _SurfaceCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('Backend setup needed', size: 22),
          const SizedBox(height: 8),
          Text(
            'The UI is ready, but Supabase returned an error. Run supabase/setup_unispace_full.sql in Supabase SQL Editor, then pull to refresh.',
            style: _body(color: AppPalette.text2, height: 1.5),
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: _body(size: 12, color: AppPalette.warn, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 160,
            child: _gradientButton('Retry', () => _loadAll()),
          ),
        ],
      ),
    );
  }

  Widget _studentHomeGreetingHeader() {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    if (hour >= 5 && hour < 12) {
      greeting = 'Good morning ☀️';
    } else if (hour >= 12 && hour < 17) {
      greeting = 'Good afternoon 🌤️';
    } else {
      greeting = 'Good evening 🌙';
    }

    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dateStr = '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
    final userName = widget.user.fullName.split(' ').first;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateStr.toUpperCase(),
            style: _body(
              size: 11,
              color: AppPalette.accent,
              weight: FontWeight.w800,
            ).copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 6),
          _heading(
            '$greeting,\n$userName',
            size: 26,
          ),
          const SizedBox(height: 4),
          Text(
            'Let\'s find your perfect study spot.',
            style: _body(size: 13, color: AppPalette.text2),
          ),
        ],
      ),
    );
  }

  Widget _studentUpcomingBookingCard() {
    final activeList = _activeBookings.where(_bookingIsUpcoming).toList();
    activeList.sort((a, b) {
      final aTime = _bookingDateTime(a, a.startTime);
      final bTime = _bookingDateTime(b, b.startTime);
      if (aTime != null && bTime != null) {
        return aTime.compareTo(bTime);
      }
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.startTime.compareTo(b.startTime);
    });

    if (activeList.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppPalette.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.accent.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Text('📚', style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Upcoming Bookings',
                    style: _body(
                      size: 15,
                      color: AppPalette.text,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Secure a seat or study room right away to focus.',
                    style: _body(size: 12, color: AppPalette.text2, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () => _navigate('rooms'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: Text(
                'Book Now',
                style: _body(size: 12, color: Colors.white, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    final booking = activeList.first;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            AppPalette.accent.withOpacity(0.12),
            AppPalette.accent2.withOpacity(0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppPalette.accent.withOpacity(0.25), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppPalette.accent.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -30,
            bottom: -30,
            child: Icon(
              Icons.stars_rounded,
              size: 120,
              color: AppPalette.accent.withOpacity(0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppPalette.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppPalette.accent.withOpacity(0.3), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppPalette.accent3,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'UPCOMING SESSION',
                            style: _body(
                              size: 9,
                              color: AppPalette.accent,
                              weight: FontWeight.w800,
                            ).copyWith(letterSpacing: 0.8),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _dateDisplay(booking.date),
                      style: _body(
                        size: 12,
                        color: AppPalette.text,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppPalette.surface.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppPalette.border),
                      ),
                      child: const Text('🚪', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            booking.roomName,
                            style: _body(
                              size: 16,
                              color: AppPalette.text,
                              weight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '📍 ${booking.roomLocation}',
                                style: _body(size: 12, color: AppPalette.text2),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '⏰ ${booking.timeSlot}',
                                style: _body(size: 12, color: AppPalette.text2),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: AppPalette.border, height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      booking.seatsBooked > 1 ? '${booking.seatsBooked} Seats Reserved' : 'Seat Reserved',
                      style: _body(
                        size: 12,
                        color: AppPalette.text2,
                        weight: FontWeight.w600,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final slip = await _repo.fetchBookingSlip(booking.id);
                          if (mounted) _showBookingSlip(slip);
                        } catch (e) {
                          _showToast('⚠️ Could not load booking slip');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppPalette.bg,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.receipt_long_rounded, size: 14),
                      label: Text(
                        'View Slip',
                        style: _body(
                          size: 11,
                          color: AppPalette.bg,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentLiveOccupancyCard() {
    final openSlots = _todaySlots.where((slot) =>
      slot.status != 'blocked_by_admin' && slot.status != 'cancellation_pending'
    ).toList();

    final totalSeatsFallback = _rooms.fold<int>(0, (sum, r) => sum + r.capacity) * 8;
    final totalSeats = _todaySlots.isEmpty
        ? totalSeatsFallback
        : openSlots.fold<int>(0, (sum, s) => sum + s.totalSeats);
    final occupiedSeats = _todaySlots.isEmpty
        ? 0
        : openSlots.fold<int>(0, (sum, s) => sum + s.bookedSeats);

    final occupancyPercent = totalSeats > 0 ? (occupiedSeats / totalSeats).clamp(0.0, 1.0) : 0.0;
    final displayPercent = (occupancyPercent * 100).round();

    Color statusColor;
    String statusTitle;
    String statusDesc;

    if (occupancyPercent <= 0.4) {
      statusColor = AppPalette.accent3;
      statusTitle = 'Low Campus Traffic';
      statusDesc = 'Plenty of quiet rooms and study seats available right now.';
    } else if (occupancyPercent <= 0.75) {
      statusColor = AppPalette.warn;
      statusTitle = 'Moderate Traffic';
      statusDesc = 'Most spaces have seats, but book ahead to secure a spot.';
    } else {
      statusColor = AppPalette.danger;
      statusTitle = 'High Campus Traffic';
      statusDesc = 'Spaces are filling up quickly. Find and secure a seat now.';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '📶 LIVE CAMPUS CAPACITY',
                style: _body(
                  size: 11,
                  color: AppPalette.text2,
                  weight: FontWeight.w700,
                ).copyWith(letterSpacing: 1.0),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$displayPercent% Occupied',
                  style: _body(
                    size: 11,
                    color: statusColor,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            statusTitle,
            style: _body(
              size: 15,
              color: AppPalette.text,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            statusDesc,
            style: _body(
              size: 12,
              color: AppPalette.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: occupancyPercent,
              minHeight: 8,
              backgroundColor: AppPalette.surface2,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Seats: $totalSeats',
                style: _body(size: 11, color: AppPalette.text2),
              ),
              Text(
                'Occupied: $occupiedSeats',
                style: _body(size: 11, color: AppPalette.text2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _studentQuickActionsGrid() {
    final items = [
      (
        label: 'Find a Room',
        desc: 'Browse & book seats',
        emoji: '🚪',
        color: AppPalette.accent,
        page: 'rooms',
      ),
      (
        label: 'My Schedule',
        desc: 'View reservations',
        emoji: '📅',
        color: AppPalette.warn,
        page: 'bookings',
      ),
      (
        label: 'Study Groups',
        desc: 'Collaborate with peers',
        emoji: '👥',
        color: AppPalette.accent2,
        page: 'groups',
      ),
      (
        label: 'Notifications',
        desc: 'Check alerts',
        emoji: '🔔',
        color: AppPalette.accent3,
        page: 'notifications',
      ),
    ];

    return _responsiveGrid(
      minTileWidth: 160,
      aspectRatio: 1.32,
      bottom: 24,
      children: items.map((item) {
        return InkWell(
          onTap: () => _navigate(item.page),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppPalette.surface2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppPalette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    item.emoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: _body(
                        size: 13,
                        color: AppPalette.text,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.desc,
                      style: _body(
                        size: 11,
                        color: AppPalette.text2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _studentPopularRoomCard(RoomInfo room) {
    final isAvailable = !room.isFull && !room.isPending;
    final occupancyPercent = room.capacity > 0
        ? ((room.capacity - room.available) / room.capacity * 100).round()
        : 0;

    return InkWell(
      onTap: () => _openBooking(room),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppPalette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: room.colors.isNotEmpty 
                    ? room.colors 
                    : [AppPalette.accent.withOpacity(0.4), AppPalette.accent2.withOpacity(0.4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Text(room.icon, style: const TextStyle(fontSize: 36)),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isAvailable ? AppPalette.accent3 : AppPalette.danger).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isAvailable ? 'Available' : 'Full',
                        style: _body(
                          size: 10,
                          color: isAvailable ? AppPalette.accent3 : AppPalette.danger,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    style: _body(size: 14, color: AppPalette.text, weight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '📍 ${room.location}',
                    style: _body(size: 11, color: AppPalette.text2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Capacity: ${room.capacity}',
                        style: _body(size: 10, color: AppPalette.text2),
                      ),
                      Text(
                        '⭐ ${room.rating.toStringAsFixed(1)}',
                        style: _body(size: 10, color: AppPalette.warn, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: room.capacity > 0 ? (room.capacity - room.available) / room.capacity : 0,
                      minHeight: 3,
                      backgroundColor: AppPalette.surface2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        occupancyPercent > 80
                            ? AppPalette.danger
                            : occupancyPercent > 50
                                ? AppPalette.warn
                                : AppPalette.accent3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studentPopularRoomsGrid() {
    final bookingCounts = <String, int>{};
    for (final b in _bookings) {
      if (!_bookingIsCancelled(b)) {
        bookingCounts[b.roomId] = (bookingCounts[b.roomId] ?? 0) + 1;
      }
    }
    final sortedRooms = List<RoomInfo>.from(_rooms);
    sortedRooms.sort((a, b) {
      final countA = bookingCounts[a.id] ?? 0;
      final countB = bookingCounts[b.id] ?? 0;
      return countB.compareTo(countA);
    });
    final popularRooms = sortedRooms.take(3).toList();
    if (popularRooms.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Text(
          'No rooms available currently.',
          style: _body(color: AppPalette.text2),
        ),
      );
    }
    return _responsiveGrid(
      minTileWidth: 200,
      aspectRatio: 1.1,
      bottom: 24,
      children: popularRooms.map((room) => _studentPopularRoomCard(room)).toList(),
    );
  }

  Widget _studentHome() {
    final now = DateTime.now();
    final upcomingEvents = _events.where((e) {
      final eDate = DateTime.tryParse(e.date);
      if (eDate == null) return false;
      return !eDate.isBefore(DateTime(now.year, now.month, now.day));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _studentHomeGreetingHeader(),
        _studentUpcomingBookingCard(),
        _studentLiveOccupancyCard(),
        _studentHomeEventsCard(upcomingEvents),
        _sectionHeader(
          '⚡ Quick Shortcuts',
        ),
        _studentQuickActionsGrid(),
        _sectionHeader(
          '🔥 Popular Rooms Right Now',
          action: 'View All →',
          onAction: () => _navigate('rooms'),
        ),
        _studentPopularRoomsGrid(),
      ],
    ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.03, curve: Curves.easeOutCubic);
  }

  Widget _studentHomeEventsCard(List<EventInfo> events) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            '📅 Upcoming Events',
            action: 'View All →',
            onAction: () => _navigate('student-events'),
          ),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: events.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final event = events[index];
                return _studentHomeHorizontalEventCard(event);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentHomeHorizontalEventCard(EventInfo event) {
    return Container(
      width: 290,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppPalette.accent2.withOpacity(0.12),
            AppPalette.accent.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.accent2.withOpacity(0.25), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppPalette.accent2.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.accent2.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppPalette.accent2.withOpacity(0.30)),
                ),
                child: Text(
                  'Campus Event',
                  style: _body(size: 9, color: AppPalette.accent2, weight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              Text(
                event.displayDate,
                style: _body(size: 11, color: AppPalette.text2, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            event.name,
            style: _body(size: 14, weight: FontWeight.bold, color: AppPalette.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          if (event.description.isNotEmpty)
            Expanded(
              child: Text(
                event.description,
                style: _body(size: 11, color: AppPalette.text2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 12, color: AppPalette.accent2),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  event.place,
                  style: _body(size: 11, color: AppPalette.text2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (event.duration.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Icon(Icons.schedule_outlined, size: 12, color: AppPalette.accent2),
                const SizedBox(width: 4),
                Text(
                  event.duration,
                  style: _body(size: 11, color: AppPalette.text2),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _roomsPage() {
    final filtered = _filterRooms(_rooms);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'Browse Rooms',
          'Find and book study rooms in real-time across campus',
        ),
        _chips(
          [
            'All Rooms',
            'Available',
            'Computers',
            'Projector',
            '≥ 20 Seats',
            'RKB',
            'RAB',
          ],
          _activeRoomFilter,
          (value) => setState(() => _activeRoomFilter = value),
        ),
        filtered.isEmpty
            ? _emptyState(
                'No matching rooms',
                'Try another filter or ask Admin to add rooms.',
              )
            : _roomGrid(filtered),
      ],
    );
  }

  List<RoomInfo> _filterRooms(List<RoomInfo> rooms) {
    switch (_activeRoomFilter) {
      case 'Available':
        return rooms.where((r) => !r.isFull && !r.isPending).toList();
      case 'Computers':
        return rooms
            .where(
              (r) => r.tags.any((t) => t.toLowerCase().contains('computer')),
            )
            .toList();
      case 'Projector':
        return rooms
            .where(
              (r) => r.tags.any((t) => t.toLowerCase().contains('projector')),
            )
            .toList();
      case '≥ 20 Seats':
        return rooms.where((r) => r.capacity >= 20).toList();
      case 'RKB':
        return rooms
            .where((r) => r.building.toLowerCase().contains('rkb'))
            .toList();
      case 'RAB':
        return rooms
            .where((r) => r.building.toLowerCase().contains('rab'))
            .toList();
      default:
        return rooms;
    }
  }

  Widget _myBookingsPage() {
    final bookings = _filteredBookings(_bookings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'My Bookings',
          'Track your upcoming and past room reservations',
        ),
        _chips(
          ['All', 'Upcoming', 'Completed', 'Cancelled'],
          _activeBookingFilter,
          (value) => setState(() => _activeBookingFilter = value),
        ),
        bookings.isEmpty
            ? _emptyState('No bookings yet', 'Book a seat from Browse Rooms.')
            : _bookingTable(bookings, studentActions: true),
      ],
    );
  }

  List<BookingInfo> _filteredBookings(List<BookingInfo> bookings) {
    switch (_activeBookingFilter) {
      case 'Upcoming':
        return bookings.where(_bookingIsUpcoming).toList();
      case 'Completed':
        return bookings.where(_bookingIsCompleted).toList();
      case 'Cancelled':
        return bookings.where(_bookingIsCancelled).toList();
      default:
        return bookings;
    }
  }

  bool _bookingIsCancelled(BookingInfo booking) {
    final normalized = booking.status.toLowerCase().trim();
    return normalized == 'cancelled' || normalized == 'canceled';
  }

  bool _bookingIsCompleted(BookingInfo booking) {
    if (_bookingIsCancelled(booking)) return false;
    final normalized = booking.status.toLowerCase().trim();
    if (normalized == 'completed') return true;
    final end = _bookingDateTime(booking, booking.endTime);
    if (end == null) return false;
    return !DateTime.now().isBefore(end);
  }

  bool _bookingIsUpcoming(BookingInfo booking) {
    if (_bookingIsCancelled(booking)) return false;
    if (booking.status.toLowerCase().trim() == 'completed') return false;
    final end = _bookingDateTime(booking, booking.endTime);
    if (end == null) return false;
    return DateTime.now().isBefore(end);
  }

  String _bookingCurrentStatus(BookingInfo booking) {
    if (_bookingIsCancelled(booking)) return 'cancelled';
    if (_bookingIsCompleted(booking)) return 'completed';
    if (booking.status.toLowerCase().trim() == 'pending') return 'pending';
    if (booking.status.toLowerCase().trim() == 'active') return 'active';
    return 'confirmed';
  }

  DateTime? _bookingDateTime(BookingInfo booking, String timeText) {
    final date = DateTime.tryParse(booking.date);
    if (date == null || timeText.trim().isEmpty) return null;

    var raw = timeText.trim().toUpperCase();
    final hasAm = raw.endsWith('AM');
    final hasPm = raw.endsWith('PM');
    if (hasAm || hasPm) raw = raw.substring(0, raw.length - 2).trim();
    raw = raw
        .replaceAll(RegExp(r'[^0-9:\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');

    final parts = raw.split(':');
    var hour = int.tryParse(parts.isNotEmpty ? parts[0].trim() : '') ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1].trim() : '') ?? 0;

    if (hasPm && hour < 12) hour += 12;
    if (hasAm && hour == 12) hour = 0;

    hour = hour.clamp(0, 23);
    final clampMinute = minute.clamp(0, 59);

    return DateTime(date.year, date.month, date.day, hour, clampMinute);
  }

  Widget _groupsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'Group Study',
          'Create date and time-slot based study groups, request to join, and manage members.',
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 190,
              child: _gradientButton('＋ Create Group', _showCreateGroupDialog),
            ),
            SizedBox(
              width: 240,
              child: _outlineButton(
                'ℹ️ Joining needs admin approval',
                _showJoinGroupDialog,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _groups.isEmpty
            ? _emptyState(
                'No study groups yet',
                'Create the first date and time-slot based group.',
              )
            : _responsiveGrid(
                minTileWidth: 380,
                aspectRatio: 1.10,
                bottom: 20,
                children: [..._groups.map(_groupCard), _createGroupCard()],
              ),
      ],
    );
  }

  Widget _notificationsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader('Notifications', '$_unreadCount unread alerts'),
        _notifications.isEmpty
            ? _emptyState(
                'No notifications',
                'Booking confirmations, group invites, and approval alerts will appear here.',
              )
            : Column(children: _notifications.map(_notificationItem).toList()),
      ],
    );
  }

  Widget _profilePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'My Profile',
          'Role-based access is controlled by your institutional email',
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppPalette.accent.withOpacity(0.10),
                AppPalette.accent2.withOpacity(0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppPalette.accent.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              _avatar(widget.user.initials, size: 80, radius: 20),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heading(widget.user.fullName, size: 22),
                    const SizedBox(height: 4),
                    Text(
                      widget.user.email,
                      style: _body(size: 13, color: AppPalette.text2),
                    ),
                    const SizedBox(height: 8),
                    _roleTag(
                      widget.user.role.emojiLabel,
                      _roleColor(widget.user.role),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 24,
                      children: [
                        _profileMetric('${_bookings.length}', 'Total Bookings'),
                        _profileMetric('${_groups.length}', 'Active Groups'),
                        _profileMetric(
                          _rooms.isEmpty
                              ? '0'
                              : (_rooms
                                            .map((r) => r.rating)
                                            .reduce((a, b) => a + b) /
                                        _rooms.length)
                                    .toStringAsFixed(1),
                          'Avg Room Rating',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeader('⚙️ Settings'),
        _SurfaceCard(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              _settingItem('👤', 'Edit Profile', AppPalette.accent),
              _settingItem(
                '🔔',
                'Notification Preferences',
                AppPalette.accent3,
              ),
              _settingItem('🔒', 'Privacy & Security', AppPalette.accent2),
              _settingItem('🌙', 'Appearance', AppPalette.warn),
              _settingItem(
                '🚪',
                'Log Out',
                AppPalette.danger,
                danger: true,
                onTap: widget.onSignOut,
              ),
            ],
          ),
        ),
      ],
    );
  }

  BookingInfo? _latestUpcomingClass() {
    final upcoming = _bookings.where((b) => _bookingIsUpcoming(b)).toList();
    if (upcoming.isEmpty) return null;
    upcoming.sort((a, b) {
      final aTime = _bookingDateTime(a, a.startTime);
      final bTime = _bookingDateTime(b, b.startTime);
      if (aTime == null || bTime == null) return 0;
      return aTime.compareTo(bTime);
    });
    return upcoming.first;
  }

  Widget _teacherDashboard() {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    if (hour >= 5 && hour < 12) {
      greeting = 'Good morning';
    } else if (hour >= 12 && hour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }
    final teacherName = widget.user.fullName.split(' ').first;

    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';

    final nextClass = _latestUpcomingClass();
    final ownRequests = _requests.length;
    final activeAssigned = _bookings.where((b) => b.status == 'active' || b.status == 'confirmed').length;

    // Upcoming events preview (next 2 events)
    final upcomingEvents = _events.where((e) {
      final eDate = DateTime.tryParse(e.date);
      if (eDate == null) return false;
      return !eDate.isBefore(DateTime(now.year, now.month, now.day));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Greeting Header ──────────────────────────────────────────
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateStr.toUpperCase(),
                      style: _body(size: 11, color: AppPalette.accent3, weight: FontWeight.w800)
                          .copyWith(letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$greeting, ',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 26, fontWeight: FontWeight.w400, color: AppPalette.text,
                            ),
                          ),
                          TextSpan(
                            text: teacherName,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 26, fontWeight: FontWeight.w800, color: AppPalette.text,
                            ),
                          ),
                          const TextSpan(text: ' 👨‍🏫', style: TextStyle(fontSize: 22)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Welcome to your UniSpace teacher dashboard.',
                      style: _body(size: 13, color: AppPalette.text2),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _dashboardStatBadge('🏫 $activeAssigned Active Rooms'),
                        const SizedBox(width: 8),
                        _dashboardStatBadge('⏳ $ownRequests Total Requests'),
                      ],
                    ),
                  ],
                ),
              ),
              // Live updates indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppPalette.accent3.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppPalette.accent3.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(color: AppPalette.accent3, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('Live updates', style: _body(size: 11, color: AppPalette.accent3, weight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Quick Action Cards ─────────────────────────────────────────
        Text(
          'QUICK ACTIONS',
          style: _body(size: 11, color: AppPalette.text3, weight: FontWeight.w800).copyWith(letterSpacing: 1.4),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _quickActionCard(
                icon: Icons.meeting_room_rounded,
                label: 'Assigned Rooms',
                color: AppPalette.accent,
                onTap: () => _navigate('teacher-assigned-rooms'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _quickActionCard(
                icon: Icons.event_rounded,
                label: 'University Events',
                color: AppPalette.accent2,
                onTap: () => _navigate('teacher-events'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // ── Next Class Section ────────────────────────────────────────
        Text(
          'NEXT CLASS SCHEDULE',
          style: _body(size: 11, color: AppPalette.text3, weight: FontWeight.w800).copyWith(letterSpacing: 1.4),
        ),
        const SizedBox(height: 12),
        if (nextClass == null)
          _SurfaceCard(
            padding: const EdgeInsets.all(24),
            borderColor: AppPalette.border,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('📅', style: TextStyle(fontSize: 32)),
                  const SizedBox(height: 10),
                  Text('No upcoming classes', style: _body(size: 15, weight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('You have no upcoming admin-assigned classes.', style: _body(size: 12, color: AppPalette.text2)),
                ],
              ),
            ),
          )
        else
          _teacherNextClassCard(nextClass),

        const SizedBox(height: 28),

        // ── Upcoming University Events Card ───────────────────────────
        Text(
          'UPCOMING UNIVERSITY EVENTS',
          style: _body(size: 11, color: AppPalette.text3, weight: FontWeight.w800).copyWith(letterSpacing: 1.4),
        ),
        const SizedBox(height: 12),
        _teacherDashboardEventsCard(upcomingEvents),
      ],
    );
  }

  Widget _dashboardStatBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppPalette.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border),
      ),
      child: Text(text, style: _body(size: 11, color: AppPalette.text2, weight: FontWeight.w700)),
    );
  }

  Widget _teacherNextClassCard(BookingInfo booking) {
    final cancellable = booking.canRequestTeacherCancellation;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppPalette.accent.withOpacity(0.18), AppPalette.accent2.withOpacity(0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.accent.withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppPalette.accent.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46, height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppPalette.mainGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('🏫', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.roomName,
                      style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.text),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '📍 ${booking.roomLocation}',
                      style: _body(size: 13, color: AppPalette.text2),
                    ),
                  ],
                ),
              ),
              _statusFromText(booking.status),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.surface.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.border),
            ),
            child: Row(
              children: [
                Expanded(child: _nextClassInfoItem(Icons.calendar_today_outlined, booking.displayDate)),
                Container(width: 1, height: 20, color: AppPalette.border, margin: const EdgeInsets.symmetric(horizontal: 10)),
                Expanded(child: _nextClassInfoItem(Icons.schedule_outlined, booking.timeRange)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🧰 ${booking.facilitiesText}',
                style: _body(size: 11, color: AppPalette.text3),
              ),
              cancellable
                  ? _actionButton(
                      'Request Release',
                      AppPalette.danger,
                      () => _showTeacherRequestDialog(booking),
                    )
                  : Text(
                      booking.status == 'cancellation_pending'
                          ? 'Release Pending Approval'
                          : 'Confirmed assignment',
                      style: _body(size: 12, color: booking.status == 'cancellation_pending' ? AppPalette.warn : AppPalette.accent3, weight: FontWeight.bold),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nextClassInfoItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppPalette.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: _body(size: 12, color: AppPalette.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _teacherDashboardEventsCard(List<EventInfo> events) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.campaign_outlined, color: AppPalette.accent2, size: 20),
                  const SizedBox(width: 8),
                  Text('Upcoming University Events', style: _body(size: 15, weight: FontWeight.bold)),
                ],
              ),
              TextButton(
                onPressed: () => _navigate('teacher-events'),
                child: Text('View All', style: _body(size: 12, color: AppPalette.accent2, weight: FontWeight.bold)),
              ),
            ],
          ),
          const Divider(color: AppPalette.border, height: 16),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No university events scheduled',
                  style: _body(size: 13, color: AppPalette.text3),
                ),
              ),
            )
          else
            Column(
              children: events.take(2).map((event) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppPalette.accent2.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.event_note_rounded, color: AppPalette.accent2, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.name,
                              style: _body(size: 13, weight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${event.displayDate} • ${event.place}',
                              style: _body(size: 11, color: AppPalette.text2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  List<BookingInfo> _filteredTeacherBookings() {
    List<BookingInfo> list = _bookings;
    // Date filter
    if (_teacherDateFilter != null) {
      final dateStr = _isoDate(_teacherDateFilter!);
      list = list.where((b) => b.date == dateStr).toList();
    }
    // Building filter
    if (_teacherBuildingFilter != 'All') {
      final query = _teacherBuildingFilter.toLowerCase().trim();
      if (query == 'other') {
        list = list.where((b) => !b.roomBuilding.toLowerCase().contains('rkb') && !b.roomBuilding.toLowerCase().contains('rab')).toList();
      } else {
        list = list.where((b) => b.roomBuilding.toLowerCase().contains(query)).toList();
      }
    }
    // Status filter
    if (_teacherStatusFilter != 'All') {
      switch (_teacherStatusFilter) {
        case 'Upcoming':
          list = list.where(_bookingIsUpcoming).toList();
          break;
        case 'Completed':
          list = list.where(_bookingIsCompleted).toList();
          break;
        case 'Cancelled':
          list = list.where(_bookingIsCancelled).toList();
          break;
      }
    }
    return list;
  }

  Widget _teacherAssignedRoomsPage() {
    final filtered = _filteredTeacherBookings();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'Assigned Rooms 🏫',
          'View and filter your admin-assigned room schedules, buildings, and release requests.',
        ),

        // Filters Container
        _SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Building Filter
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Building:', style: _body(size: 13, weight: FontWeight.bold, color: AppPalette.text2)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', 'RKB', 'RAB', 'Other'].map((bldg) {
                          final isSelected = _teacherBuildingFilter == bldg;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(bldg, style: _body(size: 12, color: isSelected ? Colors.white : AppPalette.text2, weight: FontWeight.bold)),
                              selected: isSelected,
                              selectedColor: AppPalette.accent,
                              backgroundColor: AppPalette.surface2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              onSelected: (val) {
                                if (val) setState(() => _teacherBuildingFilter = bldg);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Status Filter
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Status:', style: _body(size: 13, weight: FontWeight.bold, color: AppPalette.text2)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', 'Upcoming', 'Completed', 'Cancelled'].map((status) {
                          final isSelected = _teacherStatusFilter == status;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(status, style: _body(size: 12, color: isSelected ? Colors.white : AppPalette.text2, weight: FontWeight.bold)),
                              selected: isSelected,
                              selectedColor: AppPalette.accent2,
                              backgroundColor: AppPalette.surface2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              onSelected: (val) {
                                if (val) setState(() => _teacherStatusFilter = status);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Date Picker Filter
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 16, color: AppPalette.text2),
                  const SizedBox(width: 8),
                  Text('Filter by Date:', style: _body(size: 13, weight: FontWeight.bold, color: AppPalette.text2)),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _teacherDateFilter ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        builder: (context, child) => Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: AppPalette.accent,
                              surface: AppPalette.surface,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setState(() => _teacherDateFilter = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppPalette.surface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppPalette.border),
                      ),
                      child: Text(
                        _teacherDateFilter == null
                            ? 'Select Date'
                            : _dateDisplay(_isoDate(_teacherDateFilter!)),
                        style: _body(size: 13, color: _teacherDateFilter == null ? AppPalette.text3 : AppPalette.text),
                      ),
                    ),
                  ),
                  if (_teacherDateFilter != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18, color: AppPalette.danger),
                      onPressed: () => setState(() => _teacherDateFilter = null),
                      tooltip: 'Clear Date Filter',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Bookings List
        filtered.isEmpty
            ? _emptyState(
                'No assigned rooms match filters',
                'Change your building, status, or date filters to find assigned classes.',
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  return _teacherAssignedBookingCard(filtered[index]);
                },
              ),
      ],
    );
  }

  Widget _teacherEventsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'University Events 📅',
          'View upcoming programmes, guest lectures, workshops, and other events.',
        ),
        _events.isEmpty
            ? _emptyState(
                'No events scheduled',
                'Check back later for upcoming university programmes and events.',
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _events.length,
                separatorBuilder: (context, index) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final event = _events[index];
                  return _teacherEventCard(event);
                },
              ),
      ],
    );
  }

  Widget _teacherEventCard(EventInfo event) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  event.name,
                  style: _body(size: 16, weight: FontWeight.bold, color: AppPalette.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppPalette.accent2.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppPalette.accent2.withOpacity(0.30)),
                ),
                child: Text(
                  'Programme',
                  style: _body(size: 11, color: AppPalette.accent2, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (event.description.isNotEmpty) ...[
            Text(
              event.description,
              style: _body(size: 12, color: AppPalette.text2),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          _eventDetailRow(Icons.calendar_today_outlined, event.displayDate),
          const SizedBox(height: 6),
          _eventDetailRow(Icons.place_outlined, event.place),
          const SizedBox(height: 6),
          _eventDetailRow(Icons.schedule_outlined, event.duration),
          if (event.guests.isNotEmpty) ...[
            const SizedBox(height: 6),
            _eventDetailRow(Icons.people_outline_rounded, event.guests),
          ],
        ],
      ),
    );
  }

  Widget _studentEventsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'University Events 📅',
          'View upcoming programmes, guest lectures, workshops, and other events.',
        ),
        _events.isEmpty
            ? _emptyState(
                'No events scheduled',
                'Check back later for upcoming university programmes and events.',
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _events.length,
                separatorBuilder: (context, index) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final event = _events[index];
                  return _studentEventCard(event);
                },
              ),
      ],
    );
  }

  Widget _studentEventCard(EventInfo event) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  event.name,
                  style: _body(size: 16, weight: FontWeight.bold, color: AppPalette.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppPalette.accent2.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppPalette.accent2.withOpacity(0.30)),
                ),
                child: Text(
                  'Programme',
                  style: _body(size: 11, color: AppPalette.accent2, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (event.description.isNotEmpty) ...[
            Text(
              event.description,
              style: _body(size: 12, color: AppPalette.text2),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          _eventDetailRow(Icons.calendar_today_outlined, event.displayDate),
          const SizedBox(height: 6),
          _eventDetailRow(Icons.place_outlined, event.place),
          const SizedBox(height: 6),
          _eventDetailRow(Icons.schedule_outlined, event.duration),
          if (event.guests.isNotEmpty) ...[
            const SizedBox(height: 6),
            _eventDetailRow(Icons.people_outline_rounded, event.guests),
          ],
        ],
      ),
    );
  }

  Widget _teacherBookings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'Booking Management',
          'View your admin-assigned room bookings and request cancellation through Admin approval workflow',
        ),
        _bookings.isEmpty
            ? _emptyState(
                'No assigned bookings found',
                'Admin-assigned teacher room bookings will appear here.',
              )
            : _bookingTable(_bookings, teacherActions: true),
      ],
    );
  }

  Widget _teacherCancelRequests() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'Cancellation Requests',
          'Track requests submitted to Admin for approval',
        ),
        _requests.isEmpty
            ? _emptyState(
                'No requests submitted',
                'Submit a cancellation request from Booking Management.',
              )
            : Column(children: _requests.map(_cancelItem).toList()),
      ],
    );
  }

  Widget _adminDashboard() {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    if (hour >= 5 && hour < 12) {
      greeting = 'Good morning';
    } else if (hour >= 12 && hour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }
    final adminName = widget.user.fullName.split(' ').first;

    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';

    final bookingsToday = _bookings.where((b) => b.date == _isoDate(DateTime.now())).length;
    final bookingsThisWeek = List.generate(7, (i) => DateTime.now().subtract(Duration(days: 6 - i)))
        .fold<int>(0, (sum, d) => sum + _bookings.where((b) => b.date == _isoDate(d)).length);
    final activeUsers = _users.where((u) => u.status == 'active').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Greeting Header ──────────────────────────────────────────
        Container(
          margin: const EdgeInsets.only(bottom: 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateStr.toUpperCase(),
                      style: _body(size: 11, color: AppPalette.accent2, weight: FontWeight.w800)
                          .copyWith(letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$greeting, ',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 26, fontWeight: FontWeight.w400, color: AppPalette.text,
                            ),
                          ),
                          TextSpan(
                            text: adminName,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 26, fontWeight: FontWeight.w800, color: AppPalette.text,
                            ),
                          ),
                          const TextSpan(text: ' 🛠️', style: TextStyle(fontSize: 22)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Here\'s your system overview for today.',
                      style: _body(size: 13, color: AppPalette.text2),
                    ),
                  ],
                ),
              ),
              // Live indicator badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppPalette.accent3.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppPalette.accent3.withOpacity(0.30)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: const BoxDecoration(color: AppPalette.accent3, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text('Live', style: _body(size: 12, color: AppPalette.accent3, weight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── 4 Stat Cards ─────────────────────────────────────────────
        LayoutBuilder(
          builder: (ctx, c) {
            final cols = c.maxWidth > 700 ? 4 : c.maxWidth > 440 ? 2 : 1;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: cols >= 4 ? 1.45 : 1.7,
              children: [
                _adminStatCard(
                  icon: Icons.people_alt_rounded,
                  iconColor: AppPalette.accent2,
                  value: '${_users.length}',
                  label: 'Total Users',
                  sub: '$activeUsers active',
                  subColor: AppPalette.accent3,
                ),
                _adminStatCard(
                  icon: Icons.meeting_room_rounded,
                  iconColor: AppPalette.accent,
                  value: '${_rooms.length}',
                  label: 'Total Rooms',
                  sub: 'In system',
                  subColor: AppPalette.text2,
                ),
                _adminStatCard(
                  icon: Icons.today_rounded,
                  iconColor: AppPalette.accent3,
                  value: '$bookingsToday',
                  label: 'Bookings Today',
                  sub: '$bookingsThisWeek this week',
                  subColor: AppPalette.text2,
                ),
                _adminStatCard(
                  icon: Icons.pending_actions_rounded,
                  iconColor: AppPalette.warn,
                  value: '${_pendingRequests.length}',
                  label: 'Pending Approvals',
                  sub: _pendingRequests.isEmpty ? 'All clear' : 'Needs review',
                  subColor: _pendingRequests.isEmpty ? AppPalette.accent3 : AppPalette.warn,
                  highlight: _pendingRequests.isNotEmpty,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // ── Quick Actions ─────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QUICK ACTIONS',
                style: _body(size: 11, color: AppPalette.text3, weight: FontWeight.w800)
                    .copyWith(letterSpacing: 1.4),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (ctx, c) {
                  final cols = c.maxWidth > 600 ? 4 : 2;
                  return GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: c.maxWidth > 600 ? 2.6 : 2.2,
                    children: [
                      _quickActionCard(
                        icon: Icons.people_rounded,
                        label: 'User Management',
                        color: AppPalette.accent2,
                        onTap: () => _navigate('admin-users'),
                      ),
                      _quickActionCard(
                        icon: Icons.meeting_room_rounded,
                        label: 'Room Management',
                        color: AppPalette.accent,
                        onTap: () => _navigate('admin-rooms'),
                      ),
                      _quickActionCard(
                        icon: Icons.fact_check_rounded,
                        label: 'Approval Panel',
                        color: _pendingRequests.isNotEmpty ? AppPalette.warn : AppPalette.accent3,
                        badge: _pendingRequests.isNotEmpty ? '${_pendingRequests.length}' : null,
                        onTap: () => _navigate('admin-approval'),
                      ),
                      _quickActionCard(
                        icon: Icons.monitor_heart_rounded,
                        label: 'Booking Monitor',
                        color: AppPalette.accent,
                        onTap: () => _navigate('admin-monitor'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        // ── Charts Row ───────────────────────────────────────────────
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > 750;
            final children = [_barChart(), _donutChart()];
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: children[0]),
                      const SizedBox(width: 14),
                      Expanded(flex: 4, child: children[1]),
                    ],
                  )
                : Column(
                    children: [
                      children[0],
                      const SizedBox(height: 14),
                      children[1],
                    ],
                  );
          },
        ),
        const SizedBox(height: 24),

        // ── Recent Activity ──────────────────────────────────────────
        _adminRecentActivity(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _adminStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required String sub,
    required Color subColor,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight ? iconColor.withOpacity(0.40) : AppPalette.border,
          width: highlight ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: highlight ? iconColor.withOpacity(0.08) : Colors.black.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              if (highlight)
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.text,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(label, style: _body(size: 12, color: AppPalette.text2)),
              const SizedBox(height: 4),
              Text(sub, style: _body(size: 11, color: subColor, weight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    String? badge,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.22)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: _body(size: 12, weight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(badge, style: _body(size: 10, color: Colors.white, weight: FontWeight.w800)),
              ),
            ] else
              Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppPalette.text3),
          ],
        ),
      ),
    );
  }

  Widget _adminRecentActivity() {
    final recent = _bookings.take(6).toList();
    return _SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _heading('🕐 Recent Activity', size: 14),
              InkWell(
                onTap: () => _navigate('admin-monitor'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'View all →',
                    style: _body(size: 12, color: AppPalette.accent, weight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('No bookings yet', style: _body(size: 13, color: AppPalette.text2)),
              ),
            )
          else
            ...recent.asMap().entries.map((e) {
              final i = e.key;
              final b = e.value;
              final isActive = b.status == 'active' || b.status == 'confirmed';
              final statusColor = isActive
                  ? AppPalette.accent3
                  : b.status == 'cancelled'
                      ? AppPalette.danger
                      : b.status == 'pending'
                          ? AppPalette.warn
                          : AppPalette.text2;
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  border: i < recent.length - 1
                      ? const Border(bottom: BorderSide(color: AppPalette.border))
                      : null,
                ),
                child: Row(
                  children: [
                    _avatar(_initials(b.userName), size: 34, radius: 9),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.userName,
                            style: _body(size: 13, weight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${b.roomName} · ${b.displayDate}',
                            style: _body(size: 11, color: AppPalette.text2),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        b.status[0].toUpperCase() + b.status.substring(1),
                        style: _body(size: 10, color: statusColor, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }


  Widget _adminUsers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'User Management',
          'Manage all students, teachers, and admins',
        ),
        _users.isEmpty
            ? _emptyState(
                'No users found',
                'Profiles are created automatically after signup.',
              )
            : _userTable(),
      ],
    );
  }

  Widget _adminRooms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'Room Management',
          'Add/edit rooms and assign teachers to fixed 1-hour time slots',
        ),
        SizedBox(
          width: 220,
          child: _gradientButton(
            '＋ Add Room / Assign Teacher',
            () => _showRoomDialog(),
          ),
        ),
        const SizedBox(height: 16),
        _rooms.isEmpty
            ? _emptyState(
                'No rooms found',
                'Add rooms to start seat-based booking.',
              )
            : _roomGrid(_rooms, adminMode: true),
      ],
    );
  }

  Widget _adminEventsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'University Events 📅',
          'Manage upcoming university programmes, schedules, places, and guest lists.',
        ),
        SizedBox(
          width: 200,
          child: _gradientButton(
            '＋ Add New Event',
            () => _showEventDialog(),
          ),
        ),
        const SizedBox(height: 20),
        _events.isEmpty
            ? _emptyState(
                'No upcoming events found',
                'Add university programmes or events to let teachers and students view them.',
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _events.length,
                separatorBuilder: (context, index) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final event = _events[index];
                  return _adminEventCard(event);
                },
              ),
      ],
    );
  }

  Widget _adminEventCard(EventInfo event) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  event.name,
                  style: _body(size: 16, weight: FontWeight.bold, color: AppPalette.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppPalette.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppPalette.accent.withOpacity(0.30)),
                ),
                child: Text(
                  'Event',
                  style: _body(size: 11, color: AppPalette.accent, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (event.description.isNotEmpty) ...[
            Text(
              event.description,
              style: _body(size: 12, color: AppPalette.text2),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          _eventDetailRow(Icons.calendar_today_outlined, event.displayDate),
          const SizedBox(height: 6),
          _eventDetailRow(Icons.place_outlined, event.place),
          const SizedBox(height: 6),
          _eventDetailRow(Icons.schedule_outlined, event.duration),
          if (event.guests.isNotEmpty) ...[
            const SizedBox(height: 6),
            _eventDetailRow(Icons.people_outline_rounded, event.guests),
          ],
          const Divider(color: AppPalette.border, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: AppPalette.accent, size: 20),
                onPressed: () => _showEventDialog(event: event),
                tooltip: 'Edit Event',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppPalette.danger, size: 20),
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppPalette.surface,
                      title: Text('Delete Event', style: _body(size: 16, weight: FontWeight.bold)),
                      content: Text('Are you sure you want to delete this event? This action cannot be undone.', style: _body(size: 14)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text('Cancel', style: _body(color: AppPalette.text2)),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _runAction(
                              () => _repo.deleteEvent(event.id),
                              '🗑️ Event deleted successfully',
                            );
                          },
                          child: Text('Delete', style: _body(color: AppPalette.danger, weight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
                tooltip: 'Delete Event',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _eventDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppPalette.accent2),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: _body(size: 12, color: AppPalette.text2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _showEventDialog({EventInfo? event}) async {
    final name = TextEditingController(text: event?.name ?? '');
    final description = TextEditingController(text: event?.description ?? '');
    final place = TextEditingController(text: event?.place ?? '');
    final duration = TextEditingController(text: event?.duration ?? '');
    final guests = TextEditingController(text: event?.guests ?? '');
    DateTime selectedDate = event != null ? DateTime.tryParse(event.date) ?? DateTime.now() : DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: AppPalette.surface,
            title: Text(
              event == null ? 'Add University Event' : 'Edit University Event',
              style: _body(size: 18, weight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('Event Name *'),
                    _textInput(name, 'e.g. Annual Convocation 2026'),
                    const SizedBox(height: 12),
                    _fieldLabel('Description'),
                    TextField(
                      controller: description,
                      maxLines: 3,
                      style: _body(size: 14),
                      decoration: _inputDecoration('e.g. Details about the convocation program...'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Date *'),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedDate,
                                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                    builder: (context, child) => Theme(
                                      data: ThemeData.dark().copyWith(
                                        colorScheme: const ColorScheme.dark(
                                          primary: AppPalette.accent,
                                          surface: AppPalette.surface,
                                        ),
                                      ),
                                      child: child!,
                                    ),
                                  );
                                  if (picked != null) {
                                    setModalState(() => selectedDate = picked);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                  decoration: BoxDecoration(
                                    color: AppPalette.surface2,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppPalette.border),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _dateDisplay(_isoDate(selectedDate)),
                                        style: _body(size: 14),
                                      ),
                                      const Icon(Icons.calendar_today_rounded, size: 16, color: AppPalette.text2),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Duration *'),
                              _textInput(duration, 'e.g. 3 Hours or 10am-1pm'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _fieldLabel('Place / Location *'),
                    _textInput(place, 'e.g. Main Auditorium'),
                    const SizedBox(height: 12),
                    _fieldLabel('Guests / Speakers'),
                    _textInput(guests, 'e.g. Dr. John Doe, Prof. Jane Smith'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel', style: _body(color: AppPalette.text2)),
              ),
              TextButton(
                onPressed: () {
                  if (name.text.trim().isEmpty || place.text.trim().isEmpty || duration.text.trim().isEmpty) {
                    _showToast('⚠️ Please fill all required fields');
                    return;
                  }
                  Navigator.of(context).pop();
                  if (event == null) {
                    _runAction(
                      () => _repo.addEvent(
                        name: name.text.trim(),
                        description: description.text.trim(),
                        date: selectedDate,
                        place: place.text.trim(),
                        duration: duration.text.trim(),
                        guests: guests.text.trim(),
                      ),
                      '🎉 Event added successfully!',
                    );
                  } else {
                    _runAction(
                      () => _repo.updateEvent(
                        id: event.id,
                        name: name.text.trim(),
                        description: description.text.trim(),
                        date: selectedDate,
                        place: place.text.trim(),
                        duration: duration.text.trim(),
                        guests: guests.text.trim(),
                      ),
                      '✏️ Event updated successfully!',
                    );
                  }
                },
                child: Text(
                  event == null ? 'Add Event' : 'Save Changes',
                  style: _body(color: AppPalette.accent, weight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _adminApproval() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          'Approval Panel',
          'Review cancellation requests from teachers',
        ),
        _pendingRequests.isEmpty
            ? _emptyState(
                'No pending approvals',
                'Teacher cancellation requests will appear here.',
              )
            : Column(children: _pendingRequests.map(_approvalItem).toList()),
      ],
    );
  }

  Widget _adminMonitor() {
    final bookings = _filteredAdminTeacherBookings();
    final now = DateTime.now();

    // Compute counts for summary bar
    int confirmedCount = 0, activeCount = 0, completedCount = 0, cancelledCount = 0;
    for (final b in bookings) {
      final s = _bookingCurrentStatus(b);
      if (s == 'confirmed') confirmedCount++;
      else if (s == 'active') activeCount++;
      else if (s == 'completed') completedCount++;
      else if (s == 'cancelled') cancelledCount++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Modern Header ─────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppPalette.accent.withOpacity(0.15), AppPalette.accent2.withOpacity(0.10)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppPalette.accent.withOpacity(0.20)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppPalette.accent, AppPalette.accent2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.monitor_heart_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Booking Monitor', style: _body(size: 20, weight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Monitor teacher room bookings, conflicts, date filters, and slot availability',
                      style: _body(size: 12, color: AppPalette.text2, height: 1.4)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppPalette.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppPalette.accent.withOpacity(0.30)),
                ),
                child: Text('${bookings.length} booking${bookings.length == 1 ? '' : 's'}',
                  style: _body(size: 12, color: AppPalette.accent, weight: FontWeight.w700)),
              ),
            ],
          ),
        ),

        // ── Summary Chips ─────────────────────────────────────────────
        if (bookings.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _monitorChip('Confirmed', confirmedCount, AppPalette.accent),
                const SizedBox(width: 8),
                _monitorChip('Active', activeCount, AppPalette.accent3),
                const SizedBox(width: 8),
                _monitorChip('Completed', completedCount, AppPalette.text2),
                const SizedBox(width: 8),
                _monitorChip('Cancelled', cancelledCount, AppPalette.danger),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Filters ───────────────────────────────────────────────────
        _adminBookingFilters(),
        const SizedBox(height: 16),

        // ── Booking Cards ─────────────────────────────────────────────
        bookings.isEmpty
            ? _emptyState('No teacher room bookings found', 'Assign a teacher from Room Management or clear filters.')
            : _adminBookingCards(bookings),
      ],
    );
  }

  Widget _monitorChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text('$count $label', style: _body(size: 12, color: color, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _adminBookingCards(List<BookingInfo> bookings) {
    return Column(
      children: bookings.asMap().entries.map((e) {
        final b = e.value;
        final statusText = _bookingCurrentStatus(b);
        final isUpcoming = _bookingIsUpcoming(b);
        final isActive = statusText == 'active';

        final statusColor = statusText == 'cancelled'
            ? AppPalette.danger
            : statusText == 'completed'
                ? AppPalette.text2
                : statusText == 'active'
                    ? AppPalette.accent3
                    : AppPalette.accent; // confirmed

        final statusIcon = statusText == 'cancelled'
            ? '✕'
            : statusText == 'completed'
                ? '●'
                : statusText == 'active'
                    ? '▶'
                    : '●';

        final canCancel = isUpcoming || isActive;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? AppPalette.accent3.withOpacity(0.30)
                    : statusText == 'cancelled'
                        ? AppPalette.danger.withOpacity(0.15)
                        : AppPalette.border,
                width: isActive ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isActive ? AppPalette.accent3.withOpacity(0.06) : Colors.black.withOpacity(0.08),
                  blurRadius: 12, offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Avatar
                      _avatar(_initials(b.userName), size: 40, radius: 11),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.userName, style: _body(size: 14, weight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(b.roomName, style: _body(size: 12, color: AppPalette.accent), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor.withOpacity(0.30)),
                        ),
                        child: Text(
                          '$statusIcon ${_statusLabel(statusText)}',
                          style: _body(size: 11, color: statusColor, weight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Details row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppPalette.surface2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        _bookingDetailItem(Icons.meeting_room_outlined, b.roomLocation),
                        _bookingDetailDivider(),
                        _bookingDetailItem(Icons.calendar_today_outlined, b.displayDate),
                        _bookingDetailDivider(),
                        _bookingDetailItem(Icons.schedule_outlined, b.timeRange),
                      ],
                    ),
                  ),
                  // Cancel action
                  if (canCancel) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        onTap: () => _runAction(
                          () => _repo.cancelBooking(b.id),
                          '✅ Booking cancelled by Admin',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppPalette.danger.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppPalette.danger.withOpacity(0.30)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cancel_outlined, color: AppPalette.danger, size: 15),
                              const SizedBox(width: 6),
                              Text('Cancel Booking', style: _body(size: 12, color: AppPalette.danger, weight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _bookingDetailItem(IconData icon, String text) => Expanded(
    child: Row(
      children: [
        Icon(icon, size: 13, color: AppPalette.text2),
        const SizedBox(width: 5),
        Expanded(child: Text(text, style: _body(size: 11, color: AppPalette.text2), overflow: TextOverflow.ellipsis)),
      ],
    ),
  );

  Widget _bookingDetailDivider() => Container(
    width: 1, height: 16, margin: const EdgeInsets.symmetric(horizontal: 8),
    color: AppPalette.border,
  );


  Widget _bookingTable(
    List<BookingInfo> bookings, {
    bool studentActions = false,
    bool teacherActions = false,
    bool adminActions = false,
  }) {
    return _tableCard(
      headers: adminActions
          ? const ['Teacher/User', 'Room', 'Date & Slot', 'Status', 'Action']
          : const ['Room', 'Date & Time', 'Purpose', 'Status', 'Action'],
      flexes: const [2, 2, 2, 1, 1],
      rows: bookings.map((b) {
        final studentCancellable = studentActions && _bookingIsUpcoming(b);
        final teacherCancellable = b.canRequestTeacherCancellation;
        final statusText = studentActions ? _bookingCurrentStatus(b) : b.status;

        if (adminActions) {
          return [
            _userMini(_initials(b.userName), b.userName),
            _twoLine(b.roomName, b.roomLocation),
            _twoLine(b.displayDate, b.timeRange),
            _statusFromText(b.status),
            b.status == 'active' || b.status == 'confirmed'
                ? _smallIcon(
                    '✕',
                    onTap: () => _runAction(
                      () => _repo.cancelBooking(b.id),
                      '✅ Booking cancelled by Admin',
                    ),
                  )
                : _plain('—'),
          ];
        }
        return [
          _twoLine(b.roomName, b.roomLocation),
          _twoLine(b.displayDate, b.timeRange),
          _plain(b.isTeacherRoomBooking ? b.facilitiesText : b.purpose),
          _statusFromText(statusText),
          if (studentActions)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _smallIcon(
                  '🧾',
                  onTap: () async {
                    try {
                      final slip = await _repo.fetchBookingSlip(b.id);
                      if (mounted) _showBookingSlip(slip);
                    } catch (e) {
                      _showToast('⚠️ ${_friendlyError(e)}');
                    }
                  },
                ),
                if (studentCancellable)
                  _smallIcon(
                    '✕',
                    onTap: () => _runAction(
                      () => _repo.cancelBooking(b.id),
                      '✅ Booking cancelled and slot availability recalculated',
                    ),
                  ),
              ],
            )
          else if (teacherActions)
            teacherCancellable
                ? _actionButton(
                    'Request Cancel',
                    AppPalette.danger,
                    () => _showTeacherRequestDialog(b),
                  )
                : _plain(
                    b.status == 'cancellation_pending' ? 'Awaiting Admin' : '—',
                  )
          else
            _plain('—'),
        ];
      }).toList(),
    );
  }

  List<BookingInfo> _filteredAdminTeacherBookings() {
    return _bookings.where((b) {
      if (!b.isTeacherRoomBooking) return false;
      if (_adminTeacherFilter != 'all' &&
          b.userId != _adminTeacherFilter &&
          b.teacherId != _adminTeacherFilter)
        return false;
      if (_adminRoomFilter != 'all' && b.roomId != _adminRoomFilter)
        return false;
      if (_adminDateFilter != null && b.date != _isoDate(_adminDateFilter!))
        return false;
      if (_adminSlotFilter != 'all') {
        final label = fixedTeacherSlots[_adminSlotFilter] ?? '';
        if (b.timeRange != label) return false;
      }
      return true;
    }).toList();
  }

  Widget _adminBookingFilters() {
    final hasFilters = _adminTeacherFilter != 'all' || _adminRoomFilter != 'all'
        || _adminSlotFilter != 'all' || _adminDateFilter != null;

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppPalette.surface2,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: AppPalette.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.filter_list_rounded, size: 16, color: AppPalette.accent),
                const SizedBox(width: 8),
                Text('Filters', style: _body(size: 13, weight: FontWeight.w700, color: AppPalette.text)),
                const Spacer(),
                if (hasFilters)
                  InkWell(
                    onTap: () => setState(() {
                      _adminTeacherFilter = 'all';
                      _adminRoomFilter = 'all';
                      _adminSlotFilter = 'all';
                      _adminDateFilter = null;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppPalette.warn.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppPalette.warn.withOpacity(0.30)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.close_rounded, size: 13, color: AppPalette.warn),
                        const SizedBox(width: 4),
                        Text('Clear', style: _body(size: 11, color: AppPalette.warn, weight: FontWeight.w700)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          // Filter controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Teacher filter
                _filterField(
                  label: '👨‍🏫 Teacher',
                  child: DropdownButtonFormField<String>(
                    value: _adminTeacherFilter,
                    dropdownColor: AppPalette.surface2,
                    decoration: _inputDecoration('All Teachers'),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Teachers')),
                      ..._teachers.map((t) => DropdownMenuItem(
                        value: t.id,
                        child: Text('${t.fullName} • ${t.email}', overflow: TextOverflow.ellipsis),
                      )),
                    ],
                    onChanged: (v) => setState(() => _adminTeacherFilter = v ?? 'all'),
                  ),
                  width: 240,
                ),
                // Room filter
                _filterField(
                  label: '🏫 Room',
                  child: DropdownButtonFormField<String>(
                    value: _adminRoomFilter,
                    dropdownColor: AppPalette.surface2,
                    decoration: _inputDecoration('All Rooms'),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Rooms')),
                      ..._rooms.map((r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(r.name, overflow: TextOverflow.ellipsis),
                      )),
                    ],
                    onChanged: (v) => setState(() => _adminRoomFilter = v ?? 'all'),
                  ),
                  width: 200,
                ),
                // Date filter
                _filterField(
                  label: '📅 Date',
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _adminDateFilter ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 180)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        builder: (context, child) => Theme(
                          data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppPalette.accent, surface: AppPalette.surface)),
                          child: child!,
                        ),
                      );
                      if (picked != null) setState(() => _adminDateFilter = picked);
                    },
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _adminDateFilter != null ? AppPalette.accent.withOpacity(0.10) : AppPalette.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _adminDateFilter != null ? AppPalette.accent.withOpacity(0.40) : AppPalette.border),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_rounded, size: 15, color: _adminDateFilter != null ? AppPalette.accent : AppPalette.text2),
                        const SizedBox(width: 8),
                        Text(
                          _adminDateFilter == null ? 'All Dates' : _isoDate(_adminDateFilter!),
                          style: _body(size: 13, color: _adminDateFilter != null ? AppPalette.accent : AppPalette.text2, weight: FontWeight.w600),
                        ),
                        if (_adminDateFilter != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() => _adminDateFilter = null),
                            child: Icon(Icons.close_rounded, size: 15, color: AppPalette.text2),
                          ),
                        ],
                      ]),
                    ),
                  ),
                  width: 180,
                ),
                // Slot filter
                _filterField(
                  label: '🕐 Time Slot',
                  child: DropdownButtonFormField<String>(
                    value: _adminSlotFilter,
                    dropdownColor: AppPalette.surface2,
                    decoration: _inputDecoration('All Slots'),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Slots')),
                      ...fixedTeacherSlots.entries.map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      )),
                    ],
                    onChanged: (v) => setState(() => _adminSlotFilter = v ?? 'all'),
                  ),
                  width: 220,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterField({required String label, required Widget child, required double width}) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 5),
            child: Text(label, style: _body(size: 11, color: AppPalette.text2, weight: FontWeight.w600)),
          ),
          child,
        ],
      ),
    );
  }


  Widget _userTable() {
    return _tableCard(
      headers: const ['User', 'Role', 'Bookings', 'Status', 'Actions'],
      flexes: const [3, 1, 1, 1, 2],
      rows: _users.map((u) {
        final count = _bookings.where((b) => b.userId == u.id).length;
        final isActive = u.status == 'active';
        return [
          _userCell(u.initials, u.fullName, u.email),
          _roleTag(u.role.label, _roleColor(u.role)),
          _plain('$count'),
          _statusPill(
            isActive ? '● Active' : '◌ Inactive',
            isActive ? AppPalette.accent3 : AppPalette.warn,
          ),
          _actionButton('Edit', AppPalette.accent, () => _showUserDialog(u)),
        ];
      }).toList(),
    );
  }

  Future<void> _openBooking(RoomInfo room) async {
    if (_role != UniRole.student) return;
    DateTime selectedDate = DateTime.now();
    String? selectedSlot;
    Future<List<SlotAvailability>> slotFuture = _repo.fetchSlotAvailability(
      roomId: room.id,
      date: selectedDate,
    );
    final purposeController = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: _SurfaceCard(
                  padding: const EdgeInsets.all(28),
                  borderColor: AppPalette.accent.withOpacity(0.22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _heading('📍 ${room.name}', size: 18),
                          ),
                          _iconAction(
                            '✕',
                            onTap: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Seat availability is calculated separately for this room, date and time slot.',
                        style: _body(size: 12, color: AppPalette.text2),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppPalette.surface2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _miniInfo('Room Capacity', '${room.capacity}'),
                            _miniInfo(
                              'Availability',
                              'Slot Based',
                              color: AppPalette.accent3,
                              small: true,
                            ),
                            _miniInfo(
                              'Location',
                              room.location,
                              color: AppPalette.text2,
                              small: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Date'),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 45),
                            ),
                            builder: (context, child) => Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: AppPalette.accent,
                                  surface: AppPalette.surface,
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setModalState(() {
                              selectedDate = picked;
                              selectedSlot = null;
                              slotFuture = _repo.fetchSlotAvailability(
                                roomId: room.id,
                                date: selectedDate,
                              );
                            });
                          }
                        },
                        child: _fakeInput(_isoDate(selectedDate)),
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Select Time Slot'),
                      FutureBuilder<List<SlotAvailability>>(
                        future: slotFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppPalette.accent,
                                ),
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return _emptyState(
                              'Could not load slot availability',
                              _friendlyError(snapshot.error!),
                            );
                          }
                          final slots =
                              snapshot.data ?? const <SlotAvailability>[];
                          if (slots.isEmpty)
                            return _emptyState(
                              'No slots available',
                              'The fixed 8 AM to 4 PM slots are not configured for this room.',
                            );
                          return ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 360),
                            child: SingleChildScrollView(
                              child: LayoutBuilder(
                                builder: (context, c) {
                                  final twoCols = c.maxWidth > 520;
                                  return Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: slots.map((slot) {
                                      final selected =
                                          selectedSlot == slot.slotKey;
                                      final width = twoCols
                                          ? (c.maxWidth - 10) / 2
                                          : c.maxWidth;
                                      return SizedBox(
                                        width: width,
                                        child: _slotAvailabilityCard(
                                          slot,
                                          selected: selected,
                                          forAdmin: false,
                                          onTap: slot.studentSelectable
                                              ? () => setModalState(
                                                  () => selectedSlot =
                                                      slot.slotKey,
                                                )
                                              : null,
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Purpose'),
                      _textInput(
                        purposeController,
                        'e.g. DSA group study, exam prep…',
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _outlineButton(
                              'Cancel',
                              () => Navigator.of(context).pop(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _gradientButton(
                              'Confirm Booking ✓',
                              () async {
                                if (selectedSlot == null) {
                                  _showToast(
                                    '⚠️ Select an available time slot first.',
                                  );
                                  return;
                                }
                                final parts = selectedSlot!.split('|');
                                Navigator.of(context).pop();
                                try {
                                  final slip = await _repo.bookSeat(
                                    roomId: room.id,
                                    date: selectedDate,
                                    startTime: parts[0],
                                    endTime: parts[1],
                                    purpose:
                                        purposeController.text.trim().isEmpty
                                        ? 'Study'
                                        : purposeController.text.trim(),
                                  );
                                  await _loadAll(silent: true);
                                  if (mounted) _showBookingSlip(slip);
                                } catch (e) {
                                  _showToast('⚠️ ${_friendlyError(e)}');
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    purposeController.dispose();
  }

  Future<void> _showBookingSlip(BookingSlipInfo slip) async {
    _showToast('✅ Booking confirmed! Slip generated.');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: _SurfaceCard(
            padding: const EdgeInsets.all(24),
            borderColor: AppPalette.accent3.withOpacity(0.35),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppPalette.accent3.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text('✅', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _heading('Booking Confirmed', size: 20),
                          Text(
                            'Your booking slip is ready.',
                            style: _body(size: 12, color: AppPalette.text2),
                          ),
                        ],
                      ),
                    ),
                    _iconAction('✕', onTap: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 18),
                _slipRow('Booking ID', slip.slipNumber),
                _slipRow(
                  'Student',
                  '${slip.studentName} • ${slip.studentEmail}',
                ),
                _slipRow('Room', '${slip.roomName} • ${slip.roomLocation}'),
                _slipRow('Date', _dateDisplay(slip.date)),
                _slipRow('Time', slip.timeSlot),
                _slipRow('Seat', 'Seat ${slip.seatNumber}'),
                _slipRow('Status', _statusLabel(slip.status)),
                _slipRow('Created', _dateDisplay(slip.createdAt)),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _outlineButton('View My Bookings', () {
                        Navigator.pop(context);
                        _navigate('bookings');
                      }),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _gradientButton('Back to Home', () {
                        Navigator.pop(context);
                        _navigate('home');
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _slipRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: _body(
              size: 12,
              color: AppPalette.text2,
              weight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: _body(
              size: 13,
              color: AppPalette.text,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _showTeacherRequestDialog(BookingInfo booking) async {
    final controller = TextEditingController(
      text: 'Academic schedule changed / class cancellation.',
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppPalette.surface,
        title: Text(
          'Request Cancellation',
          style: _body(size: 18, weight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will not release the room immediately. It will be sent to Admin for approval.',
                style: _body(
                  size: 13,
                  color: AppPalette.warn,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${booking.roomName}\n${booking.displayDate} • ${booking.timeRange}\n${booking.facilitiesText}',
                style: _body(color: AppPalette.text2),
              ),
              const SizedBox(height: 14),
              _textInput(controller, 'Reason'),
            ],
          ),
        ),
        actions: [
          _outlineButton('Close', () => Navigator.pop(context)),
          _gradientButton('Send Request', () {
            Navigator.pop(context);
            _runAction(
              () => _repo.submitCancellationRequest(
                booking.id,
                controller.text.trim(),
              ),
              '✅ Cancellation request sent to Admin',
            );
          }),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _showCreateGroupDialog() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final maxMembers = TextEditingController(text: '10');
    String? roomId = _rooms.isNotEmpty ? _rooms.first.id : null;
    DateTime selectedDate = DateTime.now();
    String selectedSlot = fixedTeacherSlots.keys.first;
    Future<List<SlotAvailability>>? slotFuture = roomId == null
        ? null
        : _repo.fetchSlotAvailability(roomId: roomId!, date: selectedDate);

    Widget slotPicker(StateSetter setModalState) {
      if (roomId == null) {
        return _slotChoiceWrap(
          availability: const [],
          selectedSlot: selectedSlot,
          onSelect: (slot) => setModalState(() => selectedSlot = slot),
          showUnchecked: true,
        );
      }
      return FutureBuilder<List<SlotAvailability>>(
        future: slotFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(18),
              child: Center(
                child: CircularProgressIndicator(color: AppPalette.accent),
              ),
            );
          }
          if (snapshot.hasError)
            return _emptyState(
              'Slot status not loaded',
              _friendlyError(snapshot.error!),
            );
          return _slotChoiceWrap(
            availability: snapshot.data ?? const [],
            selectedSlot: selectedSlot,
            onSelect: (slot) => setModalState(() => selectedSlot = slot),
          );
        },
      );
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final slotParts = selectedSlot.split('|');
          return AlertDialog(
            backgroundColor: AppPalette.surface,
            title: Text(
              'Create Study Group',
              style: _body(size: 18, weight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _textInput(name, 'Group name'),
                    const SizedBox(height: 12),
                    _textInput(description, 'Description'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: roomId,
                      dropdownColor: AppPalette.surface2,
                      decoration: _inputDecoration('Room'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No room selected'),
                        ),
                        ..._rooms.map(
                          (r) => DropdownMenuItem<String?>(
                            value: r.id,
                            child: Text(
                              r.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setModalState(() {
                        roomId = v;
                        slotFuture = roomId == null
                            ? null
                            : _repo.fetchSlotAvailability(
                                roomId: roomId!,
                                date: selectedDate,
                              );
                      }),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null)
                          setModalState(() {
                            selectedDate = picked;
                            slotFuture = roomId == null
                                ? null
                                : _repo.fetchSlotAvailability(
                                    roomId: roomId!,
                                    date: selectedDate,
                                  );
                          });
                      },
                      child: _fakeInput(
                        'Date: ${_dateDisplay(_isoDate(selectedDate))}',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Time slot availability',
                      style: _body(size: 13, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    if (roomId == null)
                      Text(
                        'Select a room and date to check teacher/admin blocked slots.',
                        style: _body(size: 12, color: AppPalette.warn),
                      ),
                    if (roomId == null) const SizedBox(height: 8),
                    slotPicker(setModalState),
                    const SizedBox(height: 12),
                    TextField(
                      controller: maxMembers,
                      keyboardType: TextInputType.number,
                      style: _body(),
                      decoration: _inputDecoration('Maximum members'),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Selected slot: ${fixedTeacherSlots[selectedSlot]}',
                      style: _body(
                        size: 12,
                        color: AppPalette.accent3,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              _outlineButton('Close', () => Navigator.pop(context)),
              _gradientButton('Create', () {
                final groupName = name.text.trim();
                final max = int.tryParse(maxMembers.text.trim()) ?? 10;
                if (groupName.isEmpty) {
                  _showToast('⚠️ Group name is required');
                  return;
                }
                if (max < 2) {
                  _showToast('⚠️ Minimum 2 members required');
                  return;
                }
                Navigator.pop(context);
                _runAction(
                  () => _repo.createGroup(
                    name: groupName,
                    description: description.text.trim().isEmpty
                        ? 'Group Study Session'
                        : description.text.trim(),
                    roomId: roomId,
                    date: selectedDate,
                    startTime: slotParts[0],
                    endTime: slotParts[1],
                    maxMembers: max,
                  ),
                  '✅ Study group created. You are the admin.',
                );
              }),
            ],
          );
        },
      ),
    );
    name.dispose();
    description.dispose();
    maxMembers.dispose();
  }

  Future<void> _showEditGroupDialog(StudyGroupInfo group) async {
    final name = TextEditingController(text: group.name);
    final description = TextEditingController(text: group.description);
    final maxMembers = TextEditingController(text: group.maxMembers.toString());
    String? roomId = group.roomId;
    DateTime selectedDate = DateTime.tryParse(group.date) ?? DateTime.now();
    String selectedSlot = fixedTeacherSlots.entries
        .firstWhere(
          (e) => e.value == group.timeSlot,
          orElse: () => fixedTeacherSlots.entries.first,
        )
        .key;
    Future<List<SlotAvailability>>? slotFuture = roomId == null
        ? null
        : _repo.fetchSlotAvailability(roomId: roomId!, date: selectedDate);

    Widget slotPicker(StateSetter setModalState) {
      if (roomId == null) {
        return _slotChoiceWrap(
          availability: const [],
          selectedSlot: selectedSlot,
          onSelect: (slot) => setModalState(() => selectedSlot = slot),
          showUnchecked: true,
        );
      }
      return FutureBuilder<List<SlotAvailability>>(
        future: slotFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(18),
              child: Center(
                child: CircularProgressIndicator(color: AppPalette.accent),
              ),
            );
          }
          if (snapshot.hasError)
            return _emptyState(
              'Slot status not loaded',
              _friendlyError(snapshot.error!),
            );
          return _slotChoiceWrap(
            availability: snapshot.data ?? const [],
            selectedSlot: selectedSlot,
            onSelect: (slot) => setModalState(() => selectedSlot = slot),
          );
        },
      );
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final slotParts = selectedSlot.split('|');
          return AlertDialog(
            backgroundColor: AppPalette.surface,
            title: Text(
              'Edit Study Group',
              style: _body(size: 18, weight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _textInput(name, 'Group name'),
                    const SizedBox(height: 12),
                    _textInput(description, 'Description'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: roomId,
                      dropdownColor: AppPalette.surface2,
                      decoration: _inputDecoration('Room'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No room selected'),
                        ),
                        ..._rooms.map(
                          (r) => DropdownMenuItem<String?>(
                            value: r.id,
                            child: Text(
                              r.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setModalState(() {
                        roomId = v;
                        slotFuture = roomId == null
                            ? null
                            : _repo.fetchSlotAvailability(
                                roomId: roomId!,
                                date: selectedDate,
                              );
                      }),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null)
                          setModalState(() {
                            selectedDate = picked;
                            slotFuture = roomId == null
                                ? null
                                : _repo.fetchSlotAvailability(
                                    roomId: roomId!,
                                    date: selectedDate,
                                  );
                          });
                      },
                      child: _fakeInput(
                        'Date: ${_dateDisplay(_isoDate(selectedDate))}',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Time slot availability',
                      style: _body(size: 13, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    slotPicker(setModalState),
                    const SizedBox(height: 12),
                    TextField(
                      controller: maxMembers,
                      keyboardType: TextInputType.number,
                      style: _body(),
                      decoration: _inputDecoration('Maximum members'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              _outlineButton('Close', () => Navigator.pop(context)),
              _gradientButton('Save', () {
                final groupName = name.text.trim();
                final max =
                    int.tryParse(maxMembers.text.trim()) ?? group.maxMembers;
                if (groupName.isEmpty) {
                  _showToast('⚠️ Group name is required');
                  return;
                }
                if (max < group.memberCount) {
                  _showToast(
                    '⚠️ Maximum members cannot be less than current members',
                  );
                  return;
                }
                Navigator.pop(context);
                _runAction(
                  () => _repo.updateGroup(
                    groupId: group.id,
                    name: groupName,
                    description: description.text.trim().isEmpty
                        ? 'Group Study Session'
                        : description.text.trim(),
                    roomId: roomId,
                    date: selectedDate,
                    startTime: slotParts[0],
                    endTime: slotParts[1],
                    maxMembers: max,
                  ),
                  '✅ Study group updated.',
                );
              }),
            ],
          );
        },
      ),
    );
    name.dispose();
    description.dispose();
    maxMembers.dispose();
  }

  Future<void> _confirmDeleteGroup(StudyGroupInfo group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppPalette.surface,
        title: Text(
          'Delete Study Group?',
          style: _body(size: 18, weight: FontWeight.w800),
        ),
        content: Text(
          'This will remove "${group.name}" from active groups and notify approved members.',
          style: _body(color: AppPalette.text2, height: 1.5),
        ),
        actions: [
          _outlineButton('Cancel', () => Navigator.pop(context, false)),
          _gradientButton('Delete', () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (confirmed != true) return;
    _runAction(() => _repo.deleteGroup(group.id), '✅ Study group removed.');
  }

  Widget _slotChoiceWrap({
    required List<SlotAvailability> availability,
    required String selectedSlot,
    required ValueChanged<String> onSelect,
    bool showUnchecked = false,
  }) {
    SlotAvailability? availabilityFor(String key) {
      for (final a in availability) {
        if (a.slotKey == key) return a;
      }
      return null;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: fixedTeacherSlots.entries.map((entry) {
        final a = availabilityFor(entry.key);
        final isBlocked = a?.isBlockedByAdmin ?? false;
        final isFull = a?.isFullyBooked ?? false;
        final selectable = !isBlocked && !isFull;
        final selected = selectedSlot == entry.key;
        final color = isBlocked
            ? AppPalette.danger
            : isFull
            ? AppPalette.warn
            : selected
            ? AppPalette.accent
            : AppPalette.accent3;
        final label = showUnchecked
            ? 'Not checked'
            : (a?.statusLabel ?? 'Available');
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: selectable ? () => onSelect(entry.key) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(
                isBlocked
                    ? 0.18
                    : selected
                    ? 0.18
                    : 0.10,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: color.withOpacity(isBlocked || selected ? 0.70 : 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.value,
                        style: _body(
                          size: 12,
                          color: AppPalette.text,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (selected)
                      const Text(
                        '✓',
                        style: TextStyle(
                          color: AppPalette.accent3,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (isBlocked)
                      const Text(
                        ' ⛔',
                        style: TextStyle(color: AppPalette.danger),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _body(size: 11, color: color, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _showJoinGroupDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppPalette.surface,
        title: Text(
          'Join by Request',
          style: _body(size: 18, weight: FontWeight.w800),
        ),
        content: Text(
          'Students now join a study group by opening a group card and sending a request with Name, Contact Number, Batch, and Department. The group admin must approve before the student becomes a member.',
          style: _body(color: AppPalette.text2, height: 1.5),
        ),
        actions: [_gradientButton('Got it', () => Navigator.pop(context))],
      ),
    );
  }

  Future<void> _showJoinRequestDialog(StudyGroupInfo group) async {
    final name = TextEditingController(text: widget.user.fullName);
    final contact = TextEditingController();
    final batch = TextEditingController();
    final department = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppPalette.surface,
        title: Text(
          'Request to Join',
          style: _body(size: 18, weight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: _body(
                    size: 14,
                    color: AppPalette.accent,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                _textInput(name, 'Name'),
                const SizedBox(height: 12),
                _textInput(contact, 'Contact Number'),
                const SizedBox(height: 12),
                _textInput(batch, 'Batch'),
                const SizedBox(height: 12),
                _textInput(department, 'Department'),
              ],
            ),
          ),
        ),
        actions: [
          _outlineButton('Close', () => Navigator.pop(context)),
          _gradientButton('Send Request', () {
            if ([
              name,
              contact,
              batch,
              department,
            ].any((c) => c.text.trim().isEmpty)) {
              _showToast('⚠️ Please fill all request fields');
              return;
            }
            Navigator.pop(context);
            _runAction(
              () => _repo.requestToJoinGroup(
                groupId: group.id,
                name: name.text.trim(),
                contact: contact.text.trim(),
                batch: batch.text.trim(),
                department: department.text.trim(),
              ),
              '✅ Join request sent to group admin.',
            );
          }),
        ],
      ),
    );
    name.dispose();
    contact.dispose();
    batch.dispose();
    department.dispose();
  }

  Future<void> _showMembersSheet(StudyGroupInfo group) async {
    final userMap = {for (final u in _users) u.id: u};
    final status = await _repo.groupUserStatus(group.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: _SurfaceCard(
            padding: const EdgeInsets.all(22),
            child: FutureBuilder<List<GroupMemberInfo>>(
              future: _repo.fetchGroupMembers(group.id, userMap),
              builder: (context, snapshot) {
                final members = snapshot.data ?? const <GroupMemberInfo>[];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _heading('Group Members', size: 20),
                        const Spacer(),
                        _iconAction('✕', onTap: () => Navigator.pop(context)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.name} • ${group.memberCount}/${group.maxMembers} joined',
                      style: _body(size: 12, color: AppPalette.text2),
                    ),
                    const SizedBox(height: 16),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (members.isEmpty)
                      _emptyState(
                        'No members found',
                        'Approved members will appear here.',
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 520),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: members.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final m = members[index];
                            return _SurfaceCard(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _avatar(
                                    _initials(m.name),
                                    size: 42,
                                    radius: 12,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                m.name,
                                                style: _body(
                                                  weight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            _statusPill(
                                              m.isAdmin ? 'Admin' : 'Member',
                                              m.isAdmin
                                                  ? AppPalette.accent
                                                  : AppPalette.accent3,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Contact: ${m.contact}',
                                          style: _body(
                                            size: 12,
                                            color: AppPalette.text2,
                                          ),
                                        ),
                                        Text(
                                          'Batch: ${m.batch}',
                                          style: _body(
                                            size: 12,
                                            color: AppPalette.text2,
                                          ),
                                        ),
                                        Text(
                                          'Department: ${m.department}',
                                          style: _body(
                                            size: 12,
                                            color: AppPalette.text2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (status == 'admin' && !m.isAdmin)
                                    _actionButton(
                                      'Remove',
                                      AppPalette.danger,
                                      () {
                                        Navigator.pop(context);
                                        _runAction(
                                          () => _repo.removeGroupMember(
                                            groupId: group.id,
                                            memberUserId: m.userId,
                                          ),
                                          '✅ Member removed.',
                                        );
                                      },
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showJoinRequestsSheet(StudyGroupInfo group) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: _SurfaceCard(
            padding: const EdgeInsets.all(22),
            child: FutureBuilder<List<GroupJoinRequestInfo>>(
              future: _repo.fetchGroupJoinRequests(group.id),
              builder: (context, snapshot) {
                final requests =
                    (snapshot.data ?? const <GroupJoinRequestInfo>[])
                        .where((r) => r.status == 'pending')
                        .toList();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _heading('Join Requests', size: 20),
                        const Spacer(),
                        _iconAction('✕', onTap: () => Navigator.pop(context)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      group.name,
                      style: _body(size: 12, color: AppPalette.text2),
                    ),
                    const SizedBox(height: 16),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (requests.isEmpty)
                      _emptyState(
                        'No pending requests',
                        'New requests will appear here instantly.',
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 520),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: requests.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final r = requests[index];
                            return _SurfaceCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _avatar(
                                        _initials(r.name),
                                        size: 42,
                                        radius: 12,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r.name,
                                              style: _body(
                                                weight: FontWeight.w800,
                                              ),
                                            ),
                                            Text(
                                              _relativeTime(r.requestedAt),
                                              style: _body(
                                                size: 11,
                                                color: AppPalette.text3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _statusPill('Pending', AppPalette.warn),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Contact: ${r.contact}',
                                    style: _body(
                                      size: 12,
                                      color: AppPalette.text2,
                                    ),
                                  ),
                                  Text(
                                    'Batch: ${r.batch}',
                                    style: _body(
                                      size: 12,
                                      color: AppPalette.text2,
                                    ),
                                  ),
                                  Text(
                                    'Department: ${r.department}',
                                    style: _body(
                                      size: 12,
                                      color: AppPalette.text2,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      _actionButton(
                                        '✅ Approve',
                                        AppPalette.accent3,
                                        () {
                                          Navigator.pop(context);
                                          _runAction(
                                            () =>
                                                _repo.approveGroupRequest(r.id),
                                            '✅ Request approved.',
                                          );
                                        },
                                      ),
                                      _actionButton(
                                        '✕ Reject',
                                        AppPalette.danger,
                                        () {
                                          Navigator.pop(context);
                                          _runAction(
                                            () =>
                                                _repo.rejectGroupRequest(r.id),
                                            '✕ Request rejected.',
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRoomDialog({RoomInfo? room}) async {
    final name = TextEditingController(text: room?.name ?? '');
    final building = TextEditingController(text: room?.building ?? '');
    final floor = TextEditingController(text: room?.floor.toString() ?? '1');
    final seats = TextEditingController(
      text: room?.capacity.toString() ?? '20',
    );
    final facilities = TextEditingController(
      text: room == null
          ? 'WiFi, Whiteboard, AC'
          : room.tags
                .map((t) => t.replaceAll(RegExp(r'^[^A-Za-z]+'), ''))
                .join(', '),
    );
    String? selectedTeacherId = _teachers.isNotEmpty
        ? _teachers.first.id
        : null;
    DateTime selectedDate = DateTime.now();
    final selectedSlots = <String>{};
    Future<List<SlotAvailability>>? slotFuture = room == null
        ? null
        : _repo.fetchSlotAvailability(roomId: room.id, date: selectedDate);

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          Widget slotPicker() {
            if (room == null) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fixedTeacherSlots.entries.map((entry) {
                  final selected = selectedSlots.contains(entry.key);
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setModalState(
                      () => selected
                          ? selectedSlots.remove(entry.key)
                          : selectedSlots.add(entry.key),
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppPalette.accent.withOpacity(0.18)
                            : AppPalette.surface2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? AppPalette.accent
                              : AppPalette.border,
                        ),
                      ),
                      child: Text(
                        entry.value,
                        style: _body(
                          size: 12,
                          color: selected
                              ? AppPalette.accent
                              : AppPalette.text2,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            }
            return FutureBuilder<List<SlotAvailability>>(
              future: slotFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppPalette.accent,
                      ),
                    ),
                  );
                if (snapshot.hasError)
                  return _emptyState(
                    'Slot status not loaded',
                    _friendlyError(snapshot.error!),
                  );
                final slots = snapshot.data ?? const <SlotAvailability>[];
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: slots.map((slot) {
                    final selected = selectedSlots.contains(slot.slotKey);
                    return SizedBox(
                      width: 250,
                      child: _slotAvailabilityCard(
                        slot,
                        selected: selected,
                        forAdmin: true,
                        onTap: slot.adminSelectable
                            ? () => setModalState(
                                () => selected
                                    ? selectedSlots.remove(slot.slotKey)
                                    : selectedSlots.add(slot.slotKey),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                );
              },
            );
          }

          return AlertDialog(
            backgroundColor: AppPalette.surface,
            title: Text(
              room == null
                  ? 'Add Room / Assign Teacher'
                  : 'Edit Room / Assign Teacher',
              style: _body(size: 18, weight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('Room Details'),
                    _textInput(name, 'Room name'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _textInput(building, 'Building / Block'),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: _textInput(
                            floor,
                            'Floor',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: _textInput(
                              seats,
                              'Seats',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _textInput(facilities, 'Facilities comma separated'),
                    const SizedBox(height: 22),
                    _fieldLabel('Optional Admin-Assigned Teacher Booking'),
                    if (_teachers.isEmpty)
                      _fakeInput(
                        'No signed-up Teacher users found. Create a teacher account first.',
                        muted: true,
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: selectedTeacherId,
                        dropdownColor: AppPalette.surface2,
                        decoration: _inputDecoration('Select teacher'),
                        items: _teachers
                            .map(
                              (t) => DropdownMenuItem(
                                value: t.id,
                                child: Text(
                                  '${t.fullName} • ${t.email}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setModalState(() => selectedTeacherId = v),
                      ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          builder: (context, child) => Theme(
                            data: ThemeData.dark().copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: AppPalette.accent,
                                surface: AppPalette.surface,
                              ),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null)
                          setModalState(() {
                            selectedDate = picked;
                            selectedSlots.clear();
                            slotFuture = room == null
                                ? null
                                : _repo.fetchSlotAvailability(
                                    roomId: room.id,
                                    date: selectedDate,
                                  );
                          });
                      },
                      child: _fakeInput(
                        'Assigned date: ${_isoDate(selectedDate)}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Select one or multiple fixed slots. Red/grey slots are not selectable.',
                      style: _body(
                        size: 12,
                        color: AppPalette.text2,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    slotPicker(),
                    const SizedBox(height: 10),
                    Text(
                      'Conflict rule: same room + same date + same slot cannot be assigned twice. Student-booked slots are protected.',
                      style: _body(size: 11, color: AppPalette.warn),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              _outlineButton('Close', () => Navigator.pop(context)),
              _gradientButton(room == null ? 'Save Room' : 'Save Changes', () {
                Navigator.pop(context);
                final list = facilities.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                _runAction(
                  () async {
                    final roomId = room == null
                        ? await _repo.addRoom(
                            name: name.text.trim(),
                            building: building.text.trim(),
                            floor: int.tryParse(floor.text) ?? 1,
                            totalSeats: int.tryParse(seats.text) ?? 20,
                            facilities: list,
                          )
                        : room.id;
                    if (room != null) {
                      await _repo.updateRoom(
                        room,
                        name: name.text.trim(),
                        building: building.text.trim(),
                        floor: int.tryParse(floor.text),
                        totalSeats: int.tryParse(seats.text),
                        facilities: list,
                      );
                    }
                    if (selectedTeacherId != null && selectedSlots.isNotEmpty) {
                      await _repo.assignTeacherRoom(
                        roomId: roomId,
                        teacherId: selectedTeacherId!,
                        date: selectedDate,
                        slots: selectedSlots.toList(),
                      );
                    }
                  },
                  selectedTeacherId != null && selectedSlots.isNotEmpty
                      ? '✅ Room saved and teacher booking assigned!'
                      : '✅ Room saved!',
                );
              }),
            ],
          );
        },
      ),
    );
    name.dispose();
    building.dispose();
    floor.dispose();
    seats.dispose();
    facilities.dispose();
  }

  Future<void> _showUserDialog(UserProfile user) async {
    String status = user.status;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppPalette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppPalette.border),
          ),
          title: Text(
            'Edit User',
            style: _body(size: 18, weight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.fullName, style: _body(weight: FontWeight.w800)),
                Text(
                  user.email,
                  style: _body(size: 12, color: AppPalette.text2),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: status,
                  dropdownColor: AppPalette.surface2,
                  decoration: _inputDecoration('Status'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'inactive',
                      child: Text('Inactive'),
                    ),
                  ],
                  onChanged: (v) => setModalState(() => status = v ?? status),
                ),
                const SizedBox(height: 20),
                // Delete User button
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeleteUser(user);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppPalette.danger.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppPalette.danger.withOpacity(0.30)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline_rounded, color: AppPalette.danger, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Delete User',
                          style: _body(size: 13, color: AppPalette.danger, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            _outlineButton('Close', () => Navigator.pop(context)),
            _gradientButton('Save', () {
              Navigator.pop(context);
              _runAction(
                () => _repo.updateUserRoleStatus(user.id, user.role, status),
                '✅ User updated!',
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteUser(UserProfile user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (context) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppPalette.border),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppPalette.danger.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.warning_amber_rounded, color: AppPalette.danger, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Delete User',
              style: _body(size: 18, weight: FontWeight.w800),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to permanently delete this user?',
                style: _body(size: 14, color: AppPalette.text2, height: 1.5),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppPalette.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppPalette.border),
                ),
                child: Row(
                  children: [
                    _avatar(user.initials, size: 38, radius: 10),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.fullName, style: _body(size: 14, weight: FontWeight.w700)),
                          Text(user.email, style: _body(size: 12, color: AppPalette.text2)),
                          const SizedBox(height: 4),
                          _roleTag(user.role.label, _roleColor(user.role)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.danger.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.danger.withOpacity(0.20)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppPalette.danger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action will delete the user profile, all their bookings, and notifications. This cannot be undone.',
                        style: _body(size: 11, color: AppPalette.danger, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          _outlineButton('Cancel', () => Navigator.pop(context, false)),
          InkWell(
            onTap: () => Navigator.pop(context, true),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: AppPalette.danger,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Delete',
                style: _body(size: 13, color: Colors.white, weight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _runAction(
        () => _repo.deleteUser(user.id),
        '✅ User "${user.fullName}" deleted successfully',
      );
    }
  }

  Widget _roomGrid(List<RoomInfo> rooms, {bool adminMode = false}) {
    if (!adminMode) {
      return _responsiveGrid(
        minTileWidth: 280,
        aspectRatio: 0.92,
        children: rooms.map((room) => _roomCard(room, adminMode: false)).toList(),
        bottom: 28,
      );
    }
    // Admin mode: use a LayoutBuilder-driven 2-col grid on mobile, list on desktop
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        if (!isMobile) {
          // Desktop: clean vertical list of horizontal cards
          return Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              children: rooms.asMap().entries.map((e) {
                return Padding(
                  padding: EdgeInsets.only(bottom: e.key < rooms.length - 1 ? 12 : 0),
                  child: _adminRoomListCard(e.value),
                );
              }).toList(),
            ),
          );
        }
        // Mobile: 2-column grid of compact cards
        final colWidth = (constraints.maxWidth - 12) / 2;
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: rooms.map((room) => SizedBox(
              width: colWidth,
              child: _adminRoomCompactCard(room),
            )).toList(),
          ),
        );
      },
    );
  }

  // Desktop admin card — horizontal list item style
  Widget _adminRoomListCard(RoomInfo room) {
    const statusColor = AppPalette.accent3;
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            // Room icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: room.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: Text(room.icon, style: const TextStyle(fontSize: 26))),
            ),
            const SizedBox(width: 16),
            // Room info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.name, style: _body(size: 15, weight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 13, color: AppPalette.text2),
                      const SizedBox(width: 3),
                      Expanded(child: Text(room.location, style: _body(size: 12, color: AppPalette.text2), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.event_seat_rounded, size: 13, color: AppPalette.text2),
                      const SizedBox(width: 3),
                      Text('Capacity: ${room.capacity}', style: _body(size: 12, color: AppPalette.text2)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Status chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withOpacity(0.30)),
              ),
              child: Text('● Slot Based', style: _body(size: 11, color: statusColor, weight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            // Action buttons
            InkWell(
              onTap: () => _showRoomDialog(room: room),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: AppPalette.accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.accent.withOpacity(0.30)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_rounded, size: 14, color: AppPalette.accent),
                  const SizedBox(width: 6),
                  Text('Edit', style: _body(size: 12, color: AppPalette.accent, weight: FontWeight.w700)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _confirmAndDeleteRoom(room),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: AppPalette.danger.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.danger.withOpacity(0.30)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delete_outline_rounded, size: 14, color: AppPalette.danger),
                  const SizedBox(width: 6),
                  Text('Delete', style: _body(size: 12, color: AppPalette.danger, weight: FontWeight.w700)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mobile admin card — compact 2-column card
  Widget _adminRoomCompactCard(RoomInfo room) {
    const statusColor = AppPalette.accent3;
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coloured header strip
          Container(
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: room.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Stack(
              children: [
                Center(child: Text(room.icon, style: const TextStyle(fontSize: 28))),
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.30), borderRadius: BorderRadius.circular(20)),
                    child: Text('● Slot', style: _body(size: 9, color: statusColor, weight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          // Info section
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(room.name, style: _body(size: 13, weight: FontWeight.w800), overflow: TextOverflow.ellipsis, maxLines: 1),
                const SizedBox(height: 3),
                Text(room.location, style: _body(size: 11, color: AppPalette.text2), overflow: TextOverflow.ellipsis, maxLines: 1),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.event_seat_rounded, size: 11, color: AppPalette.text2),
                  const SizedBox(width: 3),
                  Text('${room.capacity} seats', style: _body(size: 11, color: AppPalette.text2)),
                ]),
                const SizedBox(height: 10),
                // Buttons stacked vertically for narrow columns
                SizedBox(
                  width: double.infinity,
                  child: InkWell(
                    onTap: () => _showRoomDialog(room: room),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppPalette.accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppPalette.accent.withOpacity(0.30)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.edit_rounded, size: 13, color: AppPalette.accent),
                        const SizedBox(width: 5),
                        Text('Edit', style: _body(size: 12, color: AppPalette.accent, weight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: InkWell(
                    onTap: () => _confirmAndDeleteRoom(room),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppPalette.danger.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppPalette.danger.withOpacity(0.30)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.delete_outline_rounded, size: 13, color: AppPalette.danger),
                        const SizedBox(width: 5),
                        Text('Delete', style: _body(size: 12, color: AppPalette.danger, weight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Extracted confirmation dialog for room deletion (used by both card types)
  Future<void> _confirmAndDeleteRoom(RoomInfo room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppPalette.border)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppPalette.danger.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.warning_amber_rounded, color: AppPalette.danger, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text('Delete Room', style: _body(size: 16, weight: FontWeight.w800))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Delete "${room.name}"?', style: _body(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppPalette.danger.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppPalette.danger.withOpacity(0.20)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, color: AppPalette.danger, size: 15),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'This will permanently delete the room and all its bookings. This cannot be undone.',
                style: _body(size: 11, color: AppPalette.danger, height: 1.4),
              )),
            ]),
          ),
        ]),
        actions: [
          _outlineButton('Cancel', () => Navigator.pop(ctx, false)),
          InkWell(
            onTap: () => Navigator.pop(ctx, true),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(color: AppPalette.danger, borderRadius: BorderRadius.circular(10)),
              child: Text('Delete', style: _body(size: 13, color: Colors.white, weight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
    if (ok == true) _runAction(() => _repo.deleteRoom(room.id), '🗑️ Room deleted!');
  }

  Widget _roomCard(RoomInfo room, {bool adminMode = false}) {
    const statusColor = AppPalette.accent3;
    return _SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      onTap: adminMode ? null : () => _openBooking(room),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: room.colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(room.icon, style: const TextStyle(fontSize: 42)),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '● Slot Based',
                      style: _body(
                        size: 11,
                        color: statusColor,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(room.name, size: 15),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      '📍 ${room.location}',
                      style: _body(size: 12, color: AppPalette.text2),
                    ),
                    Text(
                      'Capacity: ${room.capacity}',
                      style: _body(size: 12, color: AppPalette.text2),
                    ),
                    if (!adminMode)
                      Text(
                        '⭐ ${room.rating.toStringAsFixed(1)}',
                        style: _body(size: 12, color: AppPalette.text2),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppPalette.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppPalette.border),
                  ),
                  child: Text(
                    adminMode
                        ? 'Teacher assignment uses room + date + slot conflict checking.'
                        : 'Open this room to view per-slot total seats, available seats and blocked teacher slots.',
                    style: _body(
                      size: 11,
                      color: AppPalette.text2,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: const LinearProgressIndicator(
                    value: 1,
                    minHeight: 5,
                    backgroundColor: AppPalette.surface2,
                    color: AppPalette.accent3,
                  ),
                ),
                if (!adminMode) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: room.tags.map((tag) => _tag(tag)).toList(),
                  ),
                  const SizedBox(height: 14),
                  _gradientButton(
                    'View Slot Availability',
                    () => _openBooking(room),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _outlineButton(
                          '✏️ Edit / Assign',
                          () => _showRoomDialog(room: room),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _actionButton(
                        '🗑️ Delete',
                        AppPalette.danger,
                        () => _confirmAndDeleteRoom(room),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotAvailabilityCard(
    SlotAvailability slot, {
    required bool selected,
    required bool forAdmin,
    VoidCallback? onTap,
  }) {
    final selectable = onTap != null;
    final color = slot.statusColor;
    final bg = selected
        ? AppPalette.accent.withOpacity(0.18)
        : color.withOpacity(selectable ? 0.08 : 0.12);
    final border = selected ? AppPalette.accent : color.withOpacity(0.35);
    final subtitle = slot.isBlockedByAdmin
        ? 'Teacher Assigned${slot.teacherName == null || slot.teacherName!.isEmpty ? '' : ': ${slot.teacherName}'}'
        : 'Total Seats: ${slot.totalSeats} • Available Seats: ${slot.availableSeats}';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: selectable ? 1 : 0.62,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      slot.timeSlot,
                      style: _body(
                        size: 12,
                        color: selected ? AppPalette.accent : AppPalette.text,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (selected)
                    const Text('✓', style: TextStyle(color: AppPalette.accent)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: _body(size: 11, color: AppPalette.text2, height: 1.35),
              ),
              const SizedBox(height: 8),
              _statusPill(slot.statusLabel, color),
              if (forAdmin && !selectable) ...[
                const SizedBox(height: 6),
                Text(
                  slot.isBlockedByAdmin
                      ? 'Not selectable: already blocked by Admin.'
                      : 'Not selectable: student bookings exist or no seats left.',
                  style: _body(size: 10.5, color: AppPalette.warn, height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _teacherAssignedBookingCard(BookingInfo booking) {
    final cancellable = booking.canRequestTeacherCancellation;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SurfaceCard(
        padding: const EdgeInsets.all(18),
        borderColor: booking.status == 'cancellation_pending'
            ? AppPalette.warn.withOpacity(0.35)
            : AppPalette.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppPalette.mainGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('🏫', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _heading(booking.roomName, size: 16),
                      const SizedBox(height: 4),
                      Text(
                        '📍 ${booking.roomLocation}',
                        style: _body(size: 12, color: AppPalette.text2),
                      ),
                    ],
                  ),
                ),
                _statusFromText(booking.status),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  '📅 ${booking.displayDate}',
                  style: _body(size: 12, color: AppPalette.text2),
                ),
                Text(
                  '🕓 ${booking.timeRange}',
                  style: _body(size: 12, color: AppPalette.text2),
                ),
                Text(
                  '🧰 ${booking.facilitiesText}',
                  style: _body(size: 12, color: AppPalette.text2),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: cancellable
                  ? _actionButton(
                      'Request Cancellation',
                      AppPalette.danger,
                      () => _showTeacherRequestDialog(booking),
                    )
                  : _plain(
                      booking.status == 'cancellation_pending'
                          ? 'Cancellation Pending Admin Approval'
                          : 'No action available',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupCard(StudyGroupInfo group) {
    final isOpen = !group.isFull && group.status == 'active';
    return _SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: FutureBuilder<String>(
        future: _repo.groupUserStatus(group.id),
        builder: (context, snapshot) {
          final status = snapshot.data ?? 'loading';
          Widget action;
          if (status == 'admin') {
            action = Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _gradientButton(
                        'Join Requests',
                        () => _showJoinRequestsSheet(group),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _outlineButton(
                        'Members',
                        () => _showMembersSheet(group),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _outlineButton(
                        'Edit Group',
                        () => _showEditGroupDialog(group),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dangerOutlineButton(
                        'Delete Group',
                        () => _confirmDeleteGroup(group),
                      ),
                    ),
                  ],
                ),
              ],
            );
          } else if (status == 'member') {
            action = _disabledAction('Already Joined', AppPalette.accent3);
          } else if (status == 'pending') {
            action = _disabledAction('Request Pending', AppPalette.warn);
          } else if (!isOpen) {
            action = _disabledAction('Group Full', AppPalette.warn);
          } else {
            action = Row(
              children: [
                Expanded(
                  child: _gradientButton(
                    'Request to Join',
                    () => _showJoinRequestDialog(group),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _outlineButton(
                    'Members',
                    () => _showMembersSheet(group),
                  ),
                ),
              ],
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppPalette.accent.withOpacity(0.15),
                              AppPalette.accent2.withOpacity(0.15),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('👥', style: TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _heading(group.name, size: 15),
                            const SizedBox(height: 2),
                            Text(
                              group.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _body(size: 12, color: AppPalette.text2),
                            ),
                          ],
                        ),
                      ),
                      _statusPill(
                        isOpen ? 'Open' : 'Full',
                        isOpen ? AppPalette.accent3 : AppPalette.warn,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        '📅 ${group.displayDate}',
                        style: _body(size: 12, color: AppPalette.text2),
                      ),
                      Text(
                        '🕓 ${group.timeSlot}',
                        style: _body(size: 12, color: AppPalette.text2),
                      ),
                      Text(
                        '👤 Admin: ${group.adminName}',
                        style: _body(size: 12, color: AppPalette.text2),
                      ),
                      Text(
                        '📍 ${group.roomName}',
                        style: _body(size: 12, color: AppPalette.text2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Members',
                                  style: _body(
                                    size: 11,
                                    color: AppPalette.text3,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${group.memberCount}/${group.maxMembers}',
                                  style: _body(
                                    size: 11,
                                    color: AppPalette.accent,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                minHeight: 6,
                                value: group.maxMembers == 0
                                    ? 0
                                    : (group.memberCount / group.maxMembers).clamp(
                                        0.0,
                                        1.0,
                                      ),
                                backgroundColor: AppPalette.surface2,
                                color: isOpen ? AppPalette.accent : AppPalette.warn,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (constraints.maxHeight.isFinite)
                    const Spacer()
                  else
                    const SizedBox(height: 20),
                  action,
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _disabledAction(String label, Color color) => Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Text(
      label,
      style: _body(size: 13, color: color, weight: FontWeight.w800),
    ),
  );

  Widget _createGroupCard() => _SurfaceCard(
    padding: const EdgeInsets.all(28),
    dashed: true,
    onTap: _showCreateGroupDialog,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('＋', style: _body(size: 32, color: AppPalette.text)),
          const SizedBox(height: 12),
          Text(
            'Create a New Study Group',
            style: _body(
              size: 14,
              color: AppPalette.text2,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Invite classmates & book a room',
            style: _body(size: 12, color: AppPalette.text3),
          ),
        ],
      ),
    ),
  );

  Widget _notificationItem(AppNotification n) {
    final color = switch (n.type) {
      'booking_confirmed' => AppPalette.accent3,
      'booking_cancelled' => AppPalette.danger,
      'group_invite' => AppPalette.accent,
      'group_join_request' => AppPalette.warn,
      'request_approved' => AppPalette.accent3,
      'request_rejected' => AppPalette.danger,
      'reminder' => AppPalette.warn,
      _ => AppPalette.accent,
    };
    final icon = switch (n.type) {
      'booking_confirmed' => '✅',
      'booking_cancelled' => '❌',
      'group_invite' => '👥',
      'group_join_request' => '📝',
      'request_approved' => '✅',
      'request_rejected' => '✕',
      'reminder' => '🔔',
      _ => '🔔',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: n.isRead
            ? null
            : () => _runAction(
                () => _repo.markNotificationRead(n.id),
                'Marked as read',
              ),
        child: _SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          borderColor: !n.isRead
              ? AppPalette.accent.withOpacity(0.35)
              : AppPalette.border,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!n.isRead)
                Container(
                  width: 3,
                  height: 48,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: AppPalette.accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(icon, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: _body(size: 14, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.body,
                      style: _body(
                        size: 12,
                        color: AppPalette.text2,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _relativeTime(n.createdAt),
                      style: _body(size: 11, color: AppPalette.text3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cancelItem(RoomRequestInfo request) {
    final color = request.status == 'approved'
        ? AppPalette.accent3
        : request.status == 'rejected'
        ? AppPalette.danger
        : AppPalette.warn;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                request.status == 'approved'
                    ? '✅'
                    : request.status == 'rejected'
                    ? '❌'
                    : '🕐',
                style: const TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${request.roomName} — ${request.createdAt}',
                    style: _body(size: 14, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${request.bookingDate} • ${request.timeSlot}',
                    style: _body(
                      size: 12,
                      color: AppPalette.accent3,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    request.reason,
                    style: _body(size: 12, color: AppPalette.text2),
                  ),
                ],
              ),
            ),
            _statusPill(_statusLabel(request.status), color),
          ],
        ),
      ),
    );
  }

  Widget _approvalItem(RoomRequestInfo request) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.warn.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('🏫', style: TextStyle(fontSize: 20)),
            ),
            SizedBox(
              width: 540,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${request.roomName} — requested by ${request.requesterName}',
                    style: _body(size: 14, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${request.bookingDate} • ${request.timeSlot}',
                    style: _body(
                      size: 12,
                      color: AppPalette.accent3,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    request.reason,
                    style: _body(size: 12, color: AppPalette.text2),
                  ),
                ],
              ),
            ),
            _actionButton(
              '✅ Approve',
              AppPalette.accent3,
              () => _runAction(
                () => _repo.decideRequest(request.id, true),
                '✅ Approved! Room released to students.',
              ),
            ),
            _actionButton(
              '✕ Reject',
              AppPalette.danger,
              () => _runAction(
                () => _repo.decideRequest(request.id, false),
                '✕ Request rejected. Room stays unavailable.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero({
    required String label,
    required String title,
    required String subtitle,
    required List<(String, String, Color)> stats,
    Color accent = AppPalette.accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      margin: const EdgeInsets.only(bottom: 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withOpacity(0.12),
            AppPalette.accent2.withOpacity(0.10),
            AppPalette.accent3.withOpacity(0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.20)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -80,
            top: -80,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppPalette.accent2.withOpacity(0.16),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: _body(
                  size: 12,
                  color: accent,
                  weight: FontWeight.w700,
                ).copyWith(letterSpacing: 1.5),
              ),
              const SizedBox(height: 10),
              _heading(title, size: 28),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  subtitle,
                  style: _body(size: 14, color: AppPalette.text2, height: 1.6),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 28,
                runSpacing: 16,
                children: stats
                    .map(
                      (s) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.$1,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: s.$3,
                            ),
                          ),
                          Text(
                            s.$2,
                            style: _body(size: 12, color: AppPalette.text2),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statGrid(List<Widget> cards) => _responsiveGrid(
    minTileWidth: 220,
    aspectRatio: 1.55,
    children: cards,
    bottom: 28,
  );

  Widget _statCard(
    String icon,
    String value,
    String label,
    String change,
    Color color, {
    bool down = false,
  }) => _SurfaceCard(
    padding: const EdgeInsets.all(20),
    child: Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, down ? AppPalette.danger : AppPalette.accent2],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 12),
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppPalette.text,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: _body(size: 12, color: AppPalette.text2)),
            if (change.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                change,
                style: _body(
                  size: 11,
                  color: down ? AppPalette.danger : AppPalette.accent3,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _barChart() {
    final days = List.generate(
      7,
      (i) => DateTime.now().subtract(Duration(days: 6 - i)),
    );
    final todayStr = _isoDate(DateTime.now());
    final data = LinkedHashMap<String, (double, bool)>.fromEntries(
      days.map((d) {
        final count = _bookings.where((b) => b.date == _isoDate(d)).length.toDouble();
        final isToday = _isoDate(d) == todayStr;
        return MapEntry(_weekday(d), (count, isToday));
      }),
    );
    final maxVal = data.values.map((v) => v.$1).fold<double>(1, math.max);
    final totalWeek = data.values.fold<int>(0, (s, v) => s + v.$1.toInt());

    return _SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppPalette.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bar_chart_rounded, color: AppPalette.accent, size: 16),
                  ),
                  const SizedBox(width: 10),
                  _heading('Bookings This Week', size: 14),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppPalette.accent.withOpacity(0.20)),
                ),
                child: Text(
                  '$totalWeek total',
                  style: _body(size: 11, color: AppPalette.accent, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.entries.map((entry) {
                final count = entry.value.$1;
                final isToday = entry.value.$2;
                final barHeight = 20 + (count / maxVal) * 82;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Value label
                        if (count > 0)
                          Text(
                            count.toInt().toString(),
                            style: _body(
                              size: 10,
                              color: isToday ? AppPalette.accent : AppPalette.text2,
                              weight: isToday ? FontWeight.w800 : FontWeight.w600,
                            ),
                          )
                        else
                          const SizedBox(height: 14),
                        const SizedBox(height: 4),
                        // Bar
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          height: barHeight,
                          decoration: BoxDecoration(
                            gradient: isToday
                                ? const LinearGradient(
                                    colors: [AppPalette.accent, AppPalette.accent2],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  )
                                : LinearGradient(
                                    colors: [
                                      AppPalette.accent.withOpacity(0.30),
                                      AppPalette.accent2.withOpacity(0.55),
                                    ],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  ),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            boxShadow: isToday
                                ? [
                                    BoxShadow(
                                      color: AppPalette.accent.withOpacity(0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, -3),
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Day label
                        Text(
                          entry.key,
                          style: _body(
                            size: 10,
                            color: isToday ? AppPalette.accent : AppPalette.text3,
                            weight: isToday ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                        if (isToday)
                          Container(
                            width: 4, height: 4,
                            margin: const EdgeInsets.only(top: 3),
                            decoration: const BoxDecoration(
                              color: AppPalette.accent,
                              shape: BoxShape.circle,
                            ),
                          )
                        else
                          const SizedBox(height: 7),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _donutChart() {
    final total = _rooms.isEmpty ? 1 : _rooms.length;
    final available = _rooms.where((r) => !r.isFull && !r.isPending).length;
    final booked = total - available;
    final pct = ((booked / total) * 100).round();
    final availPct = 100 - pct;

    return _SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppPalette.accent2.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.donut_large_rounded, color: AppPalette.accent2, size: 16),
              ),
              const SizedBox(width: 10),
              _heading('Room Usage', size: 14),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Donut ring
              SizedBox(
                width: 100,
                height: 100,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background track
                    SizedBox(
                      width: 100, height: 100,
                      child: CircularProgressIndicator(
                        value: 1,
                        strokeWidth: 14,
                        color: AppPalette.surface2,
                      ),
                    ),
                    // Foreground progress
                    SizedBox(
                      width: 100, height: 100,
                      child: CircularProgressIndicator(
                        value: booked / total,
                        strokeWidth: 14,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppPalette.accent),
                      ),
                    ),
                    // Center label
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$pct%',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.text,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'occupied',
                          style: _body(size: 9, color: AppPalette.text2),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              // Legend
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legendDetailed(
                      AppPalette.accent,
                      'Occupied',
                      '$booked rooms',
                      '$pct%',
                    ),
                    const SizedBox(height: 12),
                    _legendDetailed(
                      AppPalette.accent3,
                      'Available',
                      '$available rooms',
                      '$availPct%',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 1,
                      color: AppPalette.border,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: _body(size: 11, color: AppPalette.text2)),
                        Text(
                          '$total rooms',
                          style: _body(size: 11, color: AppPalette.text, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDetailed(Color color, String label, String count, String pct) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 10, height: 10,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _body(size: 12, color: AppPalette.text, weight: FontWeight.w600)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(count, style: _body(size: 10, color: AppPalette.text2)),
                Text(pct, style: _body(size: 10, color: color, weight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  Widget _legend(Color color, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: _body(size: 12, color: AppPalette.text2)),
      ],
    ),
  );

  Widget _tableCard({
    required List<String> headers,
    required List<int> flexes,
    required List<List<Widget>> rows,
  }) {
    return _SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        children: [
          _tableRow(
            headers
                .map(
                  (h) => Text(
                    h.toUpperCase(),
                    style: _body(
                      size: 10.5,
                      color: AppPalette.text3,
                      weight: FontWeight.w800,
                    ).copyWith(letterSpacing: 0.8),
                  ),
                )
                .toList(),
            flexes,
            header: true,
          ),
          ...rows.map((r) => _tableRow(r, flexes)),
        ],
      ),
    );
  }

  Widget _tableRow(
    List<Widget> cells,
    List<int> flexes, {
    bool header = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: header ? AppPalette.surface2 : Colors.transparent,
        border: const Border(bottom: BorderSide(color: AppPalette.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: List.generate(
          cells.length,
          (i) => Expanded(
            flex: i < flexes.length ? flexes[i] : 1,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: cells[i],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusFromText(String status) {
    final color = status == 'cancelled' || status == 'rejected'
        ? AppPalette.danger
        : status == 'completed' || status == 'released'
        ? AppPalette.accent
        : status == 'pending' || status == 'cancellation_pending'
        ? AppPalette.warn
        : AppPalette.accent3;
    return _statusPill(_statusLabel(status), color);
  }

  Widget _emptyState(String title, String subtitle) => _SurfaceCard(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: Column(
        children: [
          Text('📭', style: _body(size: 34)),
          const SizedBox(height: 10),
          _heading(title, size: 16),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: _body(color: AppPalette.text2),
          ),
        ],
      ),
    ),
  );

  Widget _pageHeader(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(title, size: 22),
        const SizedBox(height: 4),
        Text(subtitle, style: _body(size: 14, color: AppPalette.text2)),
      ],
    ),
  );

  Widget _sectionHeader(
    String title, {
    String? action,
    VoidCallback? onAction,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        _heading(title, size: 17),
        const Spacer(),
        if (action != null)
          InkWell(
            onTap: onAction,
            child: Text(
              action,
              style: _body(
                size: 13,
                color: AppPalette.accent,
                weight: FontWeight.w700,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _chips(
    List<String> values,
    String active,
    ValueChanged<String> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((v) {
        final selected = v == active;
        return InkWell(
          onTap: () => onChanged(v),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppPalette.accent.withOpacity(0.18)
                  : AppPalette.surface2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppPalette.accent : AppPalette.border,
              ),
            ),
            child: Text(
              v,
              style: _body(
                size: 12,
                color: selected ? AppPalette.accent : AppPalette.text2,
                weight: FontWeight.w700,
              ),
            ),
          ),
        );
      }).toList(),
    ),
  );

  Widget _responsiveGrid({
    required double minTileWidth,
    required double aspectRatio,
    required List<Widget> children,
    double bottom = 0,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final count = math.max<int>(1, (c.maxWidth / minTileWidth).floor());
        if (count == 1) {
          return Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < children.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == children.length - 1 ? 0 : 16),
                    child: children[i],
                  ),
              ],
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: children.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: aspectRatio,
            ),
            itemBuilder: (_, i) => children[i],
          ),
        );
      },
    );
  }

  Widget _miniInfo(
    String label,
    String value, {
    Color? color,
    bool small = false,
  }) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _body(size: 11, color: AppPalette.text2)),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: small ? 13 : 20,
            fontWeight: FontWeight.w800,
            color: color ?? AppPalette.text,
          ),
        ),
      ],
    ),
  );

  Widget _tag(String tag) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppPalette.surface2,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: AppPalette.border),
    ),
    child: Text(
      tag,
      style: _body(size: 10, color: AppPalette.text2, weight: FontWeight.w600),
    ),
  );

  Widget _gradientButton(String text, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: AppPalette.mainGradient,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: _body(size: 13, color: Colors.white, weight: FontWeight.w800),
        ),
      ),
    ),
  );

  Widget _outlineButton(String text, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.border),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: _body(
          size: 13,
          color: AppPalette.text2,
          weight: FontWeight.w700,
        ),
      ),
    ),
  );

  Widget _dangerOutlineButton(String text, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.danger.withOpacity(0.65)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: _body(
          size: 13,
          color: AppPalette.danger,
          weight: FontWeight.w800,
        ),
      ),
    ),
  );

  Widget _disabledButton(String text) => Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: AppPalette.surface2,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: _body(size: 13, color: AppPalette.text3, weight: FontWeight.w700),
    ),
  );

  Widget _actionButton(String text, Color color, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(
        text,
        style: _body(size: 12, color: color, weight: FontWeight.w800),
      ),
    ),
  );

  Widget _smallIcon(String text, {VoidCallback? onTap}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(7),
    child: Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppPalette.surface2,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(text, style: _body(size: 13, color: AppPalette.text2)),
    ),
  );

  Widget _iconAction(String text, {required VoidCallback onTap}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppPalette.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: _body(size: 14, color: AppPalette.text2)),
    ),
  );

  Widget _topIcon(String icon, {bool showDot = false, VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppPalette.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppPalette.border),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              if (showDot)
                Positioned(
                  top: -4,
                  right: -5,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppPalette.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _avatar(String initials, {double size = 36, double radius = 10}) =>
      Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: AppPalette.mainGradient,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Text(
          initials,
          style: _body(
            size: size * .32,
            color: Colors.white,
            weight: FontWeight.w800,
          ),
        ),
      );

  Widget _userCell(String initials, String name, String email) => Row(
    children: [
      _avatar(initials, size: 32, radius: 8),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _body(size: 13, weight: FontWeight.w700),
            ),
            Text(
              email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _body(size: 11, color: AppPalette.text2),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _userMini(String initials, String name) => Row(
    children: [
      _avatar(initials, size: 32, radius: 8),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _body(size: 13),
        ),
      ),
    ],
  );

  Widget _twoLine(String title, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _body(size: 13, weight: FontWeight.w700),
      ),
      const SizedBox(height: 2),
      Text(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _body(size: 11, color: AppPalette.text2),
      ),
    ],
  );

  Widget _plain(String text) => Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: _body(size: 13, color: AppPalette.text2),
  );

  Widget _roleTag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.13),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: _body(size: 11, color: color, weight: FontWeight.w800),
    ),
  );

  Widget _statusPill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    constraints: const BoxConstraints(minWidth: 70),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    alignment: Alignment.center,
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: _body(size: 11, color: color, weight: FontWeight.w800),
    ),
  );

  Widget _profileMetric(String value, String label) => Column(
    children: [
      Text(
        value,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppPalette.accent,
        ),
      ),
      Text(label, style: _body(size: 11, color: AppPalette.text2)),
    ],
  );

  Widget _settingItem(
    String icon,
    String label,
    Color color, {
    bool danger = false,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(icon, style: const TextStyle(fontSize: 17)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: _body(
                size: 14,
                color: danger ? AppPalette.danger : AppPalette.text,
              ),
            ),
          ),
          if (!danger) Text('›', style: _body(color: AppPalette.text3)),
        ],
      ),
    ),
  );

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: _body(
        size: 12,
        color: AppPalette.text2,
        weight: FontWeight.w800,
      ).copyWith(letterSpacing: .5),
    ),
  );

  Widget _fakeInput(String text, {bool muted = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      color: AppPalette.surface2,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppPalette.border),
    ),
    child: Text(
      text,
      style: _body(size: 14, color: muted ? AppPalette.text3 : AppPalette.text),
    ),
  );

  Widget _textInput(
    TextEditingController controller,
    String hint, {
    TextInputType? keyboardType,
  }) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    style: _body(size: 14),
    decoration: _inputDecoration(hint),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: _body(color: AppPalette.text3),
    filled: true,
    fillColor: AppPalette.surface2,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppPalette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppPalette.accent),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
  );

  Widget _toast(String message) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: AppPalette.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppPalette.accent3.withOpacity(0.3)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.35),
          blurRadius: 26,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Text(
      message,
      style: _body(
        size: 13,
        color: AppPalette.accent3,
        weight: FontWeight.w700,
      ),
    ),
  );

  Widget _gradientText(
    String text, {
    double size = 18,
    FontWeight weight = FontWeight.w700,
  }) => ShaderMask(
    shaderCallback: (bounds) => AppPalette.mainGradient.createShader(bounds),
    child: Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: Colors.white,
      ),
    ),
  );

  Widget _heading(String text, {double size = 18}) => Text(
    text,
    style: GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: FontWeight.w800,
      color: AppPalette.text,
      height: 1.18,
    ),
  );

  TextStyle _body({
    double size = 14,
    Color color = AppPalette.text,
    FontWeight weight = FontWeight.w400,
    double height = 1.35,
  }) => GoogleFonts.dmSans(
    fontSize: size,
    color: color,
    fontWeight: weight,
    height: height,
  );
}

class _SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool clip;
  final bool dashed;
  final VoidCallback? onTap;
  final Color borderColor;

  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.clip = false,
    this.dashed = false,
    this.onTap,
    this.borderColor = AppPalette.border,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: dashed ? 1.2 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: clip
            ? ClipRRect(borderRadius: BorderRadius.circular(20), child: card)
            : card,
      ),
    );
  }
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _asDouble(dynamic value, [double fallback = 0]) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

List<String> _asStringList(dynamic value) {
  if (value is List) return value.map((e) => e.toString()).toList();
  if (value is String)
    return value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  return const [];
}

String _tagLabel(String raw) {
  final l = raw.toLowerCase();
  if (l.contains('wifi')) return '📶 WiFi';
  if (l.contains('computer')) return '🖥️ Computers';
  if (l.contains('projector')) return '📽️ Projector';
  if (l.contains('mic') || l.contains('sound')) return '🎤 Audio';
  if (l.contains('ac')) return '❄️ AC';
  if (l.contains('whiteboard')) return '🖊️ Whiteboard';
  return raw;
}

String _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return '';
}

String _iconForRoom(String name, List<String> tags) {
  final text = ('$name ${tags.join(' ')}').toLowerCase();
  if (text.contains('computer') || text.contains('lab')) return '🖥️';
  if (text.contains('seminar')) return '📚';
  if (text.contains('research') || text.contains('science')) return '🔬';
  if (text.contains('media')) return '🎥';
  if (text.contains('math')) return '➕';
  if (text.contains('discussion')) return '💬';
  return '🏛️';
}

List<Color> _colorsForRoom(String name) {
  final palettes = const [
    [Color(0xFF1A237E), Color(0xFF283593)],
    [Color(0xFF1B5E20), Color(0xFF2E7D32)],
    [Color(0xFF4A148C), Color(0xFF6A1B9A)],
    [Color(0xFFBF360C), Color(0xFFE64A19)],
    [Color(0xFF006064), Color(0xFF00838F)],
    [Color(0xFF33691E), Color(0xFF558B2F)],
  ];
  return palettes[name.hashCode.abs() % palettes.length];
}

String _shortTime(String time) {
  if (time.isEmpty) return '';
  final parts = time.split(':');
  if (parts.length < 2) return time;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts[1];
  final hour = h == 0
      ? 12
      : h > 12
      ? h - 12
      : h;
  final suffix = h >= 12 ? 'PM' : 'AM';
  return m == '00' ? '$hour $suffix' : '$hour:$m $suffix';
}

String _dateDisplay(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  if (d == today) return 'Today';
  if (d == today.add(const Duration(days: 1))) return 'Tomorrow';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String _relativeTime(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  return '${diff.inDays} days ago';
}

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _inviteCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rand = math.Random.secure();
  return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'US';
  if (parts.length == 1)
    return parts.first
        .substring(0, math.min(2, parts.first.length))
        .toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

Color _roleColor(UniRole role) => switch (role) {
  UniRole.student => AppPalette.accent,
  UniRole.teacher => AppPalette.accent3,
  UniRole.admin => AppPalette.accent2,
};

String _statusLabel(String status) => switch (status) {
  'confirmed' => '● Confirmed',
  'active' => '● Active',
  'pending' => '◌ Pending',
  'cancellation_pending' => '◌ Cancellation Pending',
  'completed' => '● Completed',
  'cancelled' => '✕ Cancelled',
  'released' => '● Released',
  'approved' => '● Approved',
  'rejected' => '✕ Rejected',
  _ => status,
};

String _weekday(DateTime d) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

String _friendlyError(Object e) {
  final msg = e
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('PostgrestException(message: ', '');
  if (msg.length > 120) return '${msg.substring(0, 120)}…';
  return msg;
}
