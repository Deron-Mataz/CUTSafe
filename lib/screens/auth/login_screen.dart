import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../home_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form    = GlobalKey<FormState>();
  final _email   = TextEditingController();
  final _pass    = TextEditingController();
  bool _hide = true;

  @override
  void dispose() { _email.dispose(); _pass.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final err = await context.read<UserProvider>().signIn(_email.text, _pass.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppTheme.cutRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<UserProvider>().isLoading;
    return Scaffold(
      backgroundColor: AppTheme.cutBlue,
      body: SafeArea(
        child: Column(children: [
          // Header
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 40, 24, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_outlined, color: Colors.white, size: 44),
              SizedBox(height: 16),
              Text('CUT Safety',
                  style: TextStyle(color: Colors.white, fontSize: 28,
                      fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              SizedBox(height: 4),
              Text('Sign in to your account',
                  style: TextStyle(color: Colors.white70, fontSize: 15)),
            ]),
          ),
          // Card
          Expanded(
            child: Container(
              decoration: const BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _form,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.email_outlined)),
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Enter a valid email' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller:  _pass,
                        obscureText: _hide,
                        decoration: InputDecoration(
                          labelText:  'Password',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_hide ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _hide = !_hide),
                          ),
                        ),
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Password too short' : null,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordScreen())),
                          child: const Text('Forgot password?',
                              style: TextStyle(color: AppTheme.cutBlue)),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: loading ? null : _submit,
                        child: loading
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Sign In'),
                      ),
                      const SizedBox(height: 20),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Text("Don't have an account? "),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const RegisterScreen())),
                          child: const Text('Register',
                              style: TextStyle(color: AppTheme.cutBlue,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
