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

/// Sign up screen for student and teacher accounts
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _departmentController = TextEditingController();
  final _profileIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  UserRole _selectedDesignation = UserRole.student;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _departmentController.dispose();
    _profileIdController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleSignup() {
    if (_formKey.currentState?.validate() ?? false) {
      ref
          .read(authProvider.notifier)
          .signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            fullName: _nameController.text.trim(),
            role: _selectedDesignation,
            department: _departmentController.text.trim(),
            profileId: _profileIdController.text.trim(),
            phone: _phoneController.text.trim(),
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
            colors: [Color(0xFF0D2040), AppColors.background],
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

                  Text(
                    'Create your UniSpace account using your email',
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

                  // Email
                  CustomTextField(
                    controller: _emailController,
                    hintText: 'your.email@gmail.com',
                    labelText: 'Email Address',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!RegExp(
                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                      ).hasMatch(email)) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ).animate(delay: 500.ms).fadeIn().slideX(begin: -0.1),

                  const SizedBox(height: 18),

                  _designationDropdown()
                      .animate(delay: 550.ms)
                      .fadeIn()
                      .slideX(begin: -0.1),

                  const SizedBox(height: 18),

                  CustomTextField(
                    controller: _departmentController,
                    hintText: 'Computer Science',
                    labelText: 'Department',
                    prefixIcon: Icons.apartment_outlined,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Please enter your department'
                        : null,
                  ).animate(delay: 575.ms).fadeIn().slideX(begin: -0.1),

                  const SizedBox(height: 18),

                  CustomTextField(
                    controller: _profileIdController,
                    hintText: '111016',
                    labelText: 'ID',
                    prefixIcon: Icons.badge_outlined,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Please enter your ID'
                        : null,
                  ).animate(delay: 600.ms).fadeIn().slideX(begin: -0.1),

                  const SizedBox(height: 18),

                  CustomTextField(
                    controller: _phoneController,
                    hintText: '01700000000',
                    labelText: 'Phone Number',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Please enter your phone number'
                        : null,
                  ).animate(delay: 625.ms).fadeIn().slideX(begin: -0.1),

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
                    text: 'Sign Up',
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

  Widget _designationDropdown() {
    return DropdownButtonFormField<UserRole>(
      initialValue: _selectedDesignation,
      dropdownColor: AppColors.surface,
      style: AppTextStyles.bodyLarge,
      decoration: InputDecoration(
        labelText: 'Designation',
        prefixIcon: const Icon(Icons.work_outline_rounded),
        labelStyle: AppTextStyles.labelMedium,
        filled: true,
        fillColor: AppColors.surfaceLight,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
      items: const [
        DropdownMenuItem(value: UserRole.student, child: Text('Student')),
        DropdownMenuItem(value: UserRole.teacher, child: Text('Teacher')),
      ],
      onChanged: (role) {
        if (role != null) setState(() => _selectedDesignation = role);
      },
    );
  }
}
