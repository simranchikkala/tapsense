import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/services/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signup() async {
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.signUp(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (mounted) context.go('/onboarding');
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text('Create account',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                    color: kTextPrimary)),
              const SizedBox(height: 6),
              const Text('Start tracking smarter',
                style: TextStyle(fontSize: 15, color: kTextSecondary)),
              const SizedBox(height: 40),
              _field('Your name', _nameCtrl, false),
              const SizedBox(height: 14),
              _field('Email', _emailCtrl, false),
              const SizedBox(height: 14),
              _field('Password', _passwordCtrl, true),
              const SizedBox(height: 10),
              if (_error != null)
                Text(_error!, style: const TextStyle(
                    color: kError, fontSize: 13)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: kTextPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kTextPrimary))
                      : const Text('Create Account',
                          style: TextStyle(fontSize: 16,
                              fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: const Text.rich(TextSpan(children: [
                    TextSpan(text: 'Already have an account? ',
                        style: TextStyle(color: kTextSecondary)),
                    TextSpan(text: 'Sign in',
                        style: TextStyle(color: kAccent,
                            fontWeight: FontWeight.w700)),
                  ])),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, bool obscure) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w600, color: kTextSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          style: const TextStyle(color: kTextPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: kSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kAccent),
            ),
          ),
        ),
      ],
    );
  }
}