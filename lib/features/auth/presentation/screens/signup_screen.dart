import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/core/constants/app_constants.dart';
import 'package:unispace/core/widgets/custom_text_field.dart';
import 'package:unispace/core/widgets/gradient_button.dart';
import 'package:unispace/features/auth/presentation/providers/auth_provider.dart';

/// Sign up screen with role auto-detection
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  UserRole? _detectedRole;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onEmailChanged(String email) {
    final domain = email.split('@').last.toLowerCase();
    UserRole? role;
    if (domain == AppConstants.studentDomain) {
      role = UserRole.student;
    } else if (domain == AppConstants.teacherDomain) {
      role = UserRole.teacher;
    } else if (domain == AppConstants.adminDomain) {
      role = UserRole.admin;
    }
    if (role != _detectedRole) {
      setState(() => _detectedRole = role);
    }
  }

  void _handleSignup() {
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(authProvider.notifier).signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            fullName: _nameController.text.trim(),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: AppColors.error,
          ),
        );
        ref.read(authProvider.notifier).clearError();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.5, -0.3),
            radius: 1.5,
            colors: [
              Color(0xFF0D2040),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),

                  // Back button
                  GestureDetector(
                    onTap: () => context.go('/login'),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: AppColors.textPrimary,
                        size: 18,
                      ),
                    ),
                  ).animate().fadeIn(duration: 400.ms),

                  const SizedBox(height: 24),

                  // Title
                  Text('Create Account', style: AppTextStyles.h1)
                      .animate(delay: 200.ms)
                      .fadeIn()
                      .slideY(begin: 0.2),

                  const SizedBox(height: 8),

                  Text(
                    'Join UniSpace to find and book study rooms',
                    style: AppTextStyles.bodyMedium,
                  ).animate(delay: 300.ms).fadeIn(),

                  const SizedBox(height: 36),

                  // Full name
                  CustomTextField(
                    controller: _nameController,
                    hintText: 'John Doe',
                    labelText: 'Full Name',
                    prefixIcon: Icons.person_outline,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ).animate(delay: 400.ms).fadeIn().slideX(begin: -0.1),

                  const SizedBox(height: 18),

                  // Email with role detection
                  CustomTextField(
                    controller: _emailController,
                    hintText: 'your.email@student.lus.bd',
                    labelText: 'Institutional Email',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: _onEmailChanged,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      final domain = value.split('@').last.toLowerCase();
                      if (domain != AppConstants.studentDomain &&
                          domain != AppConstants.teacherDomain &&
                          domain != AppConstants.adminDomain) {
                        return 'Please use your institutional email';
                      }
                      return null;
                    },
                  ).animate(delay: 500.ms).fadeIn().slideX(begin: -0.1),

                  // Role badge
                  if (_detectedRole != null) ...[
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _getRoleColor(_detectedRole!).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _getRoleColor(_detectedRole!).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getRoleIcon(_detectedRole!),
                            size: 16,
                            color: _getRoleColor(_detectedRole!),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Role detected: ${_detectedRole!.displayName}',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: _getRoleColor(_detectedRole!),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn().scale(
                          begin: const Offset(0.9, 0.9),
                          curve: Curves.easeOutBack,
                        ),
                  ],

                  const SizedBox(height: 18),

                  // Password
                  CustomTextField(
                    controller: _passwordController,
                    hintText: '••••••••',
                    labelText: 'Password',
                    prefixIcon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textHint,
                        size: 22,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ).animate(delay: 600.ms).fadeIn().slideX(begin: -0.1),

                  const SizedBox(height: 18),

                  // Confirm password
                  CustomTextField(
                    controller: _confirmPasswordController,
                    hintText: '••••••••',
                    labelText: 'Confirm Password',
                    prefixIcon: Icons.lock_outline,
                    obscureText: _obscureConfirm,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textHint,
                        size: 22,
                      ),
                      onPressed: () {
                        setState(() => _obscureConfirm = !_obscureConfirm);
                      },
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ).animate(delay: 700.ms).fadeIn().slideX(begin: -0.1),

                  const SizedBox(height: 36),

                  // Sign up button
                  GradientButton(
                    text: 'Create Account',
                    isLoading: authState.status == AuthStatus.loading,
                    onPressed: _handleSignup,
                    icon: Icons.person_add_alt_1_rounded,
                  ).animate(delay: 800.ms).fadeIn().slideY(begin: 0.2),

                  const SizedBox(height: 24),

                  // Sign in link
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: AppTextStyles.bodyMedium,
                        ),
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          child: Text(
                            'Sign In',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate(delay: 900.ms).fadeIn(),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.student:
        return AppColors.accent;
      case UserRole.teacher:
        return AppColors.warning;
      case UserRole.admin:
        return AppColors.error;
    }
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.student:
        return Icons.school_rounded;
      case UserRole.teacher:
        return Icons.person_rounded;
      case UserRole.admin:
        return Icons.admin_panel_settings_rounded;
    }
  }
}
