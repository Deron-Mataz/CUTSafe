import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form  = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent    = false;
  bool _loading = false;

  @override
  void dispose() { _email.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    final err = await context.read<UserProvider>()
        .sendPasswordReset(_email.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (err == null) {
      setState(() => _sent = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppTheme.cutRed));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reset Password')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: _sent
          ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.mark_email_read_outlined,
                  size: 72, color: Colors.green),
              const SizedBox(height: 24),
              const Text('Email sent!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text('We sent a reset link to ${_email.text}.\nCheck your inbox.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.cutMuted)),
              const SizedBox(height: 32),
              ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to Sign In')),
            ])
          : Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const Icon(Icons.lock_reset, size: 56, color: AppTheme.cutBlue),
                  const SizedBox(height: 24),
                  const Text('Forgot your password?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                    "Enter your email and we'll send a reset link.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppTheme.cutMuted),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller:   _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined)),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Send Reset Link'),
                  ),
                ],
              ),
            ),
    ),
  );
}
