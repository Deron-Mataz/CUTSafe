import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../home_screen.dart';

const kCampuses = ['Bloemfontein Campus', 'Welkom Campus'];

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _conf = TextEditingController();
  String _campus = kCampuses.first;
  bool _hide = true;
  bool _termsAccepted = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _conf.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    // Guard: terms must be accepted
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'You must accept the Terms & Conditions to create an account.'),
          backgroundColor: AppTheme.cutRed,
        ),
      );
      return;
    }

    final err = await context.read<UserProvider>().signUp(
          email: _email.text,
          password: _pass.text,
          name: _name.text,
          campus: _campus,
        );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppTheme.cutRed));
    }
  }

  /// Opens the full Terms screen in read-only / review mode.
  void _viewTerms() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _TermsReviewScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<UserProvider>().isLoading;
    return Scaffold(
      backgroundColor: AppTheme.cutBlue,
      appBar: AppBar(
        backgroundColor: AppTheme.cutBlue,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title:
            const Text('Create Account', style: TextStyle(color: Colors.white)),
      ),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Join the CUT community safety network',
                  style: TextStyle(color: Colors.white70, fontSize: 14))),
        ),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),

                    // Full name
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline)),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 14),

                    // Email
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Email address',
                          prefixIcon: Icon(Icons.email_outlined)),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 14),

                    // Campus
                    DropdownButtonFormField<String>(
                      initialValue: _campus,
                      decoration: const InputDecoration(
                          labelText: 'Campus',
                          prefixIcon: Icon(Icons.school_outlined)),
                      items: kCampuses
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _campus = v ?? _campus),
                    ),
                    const SizedBox(height: 14),

                    // Password
                    TextFormField(
                      controller: _pass,
                      obscureText: _hide,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_hide
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Min 6 characters'
                          : null,
                    ),
                    const SizedBox(height: 14),

                    // Confirm password
                    TextFormField(
                      controller: _conf,
                      obscureText: _hide,
                      decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: Icon(Icons.lock_outline)),
                      validator: (v) =>
                          v != _pass.text ? 'Passwords do not match' : null,
                    ),
                    const SizedBox(height: 24),

                    // ── Terms & Conditions checkbox ───────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _termsAccepted
                            ? AppTheme.cutBlue.withValues(alpha: 0.05)
                            : AppTheme.cutGrey,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _termsAccepted
                              ? AppTheme.cutBlue
                              : AppTheme.cutBorder,
                        ),
                      ),
                      child: InkWell(
                        onTap: () =>
                            setState(() => _termsAccepted = !_termsAccepted),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _termsAccepted,
                                activeColor: AppTheme.cutBlue,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4)),
                                onChanged: (v) =>
                                    setState(() => _termsAccepted = v ?? false),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.cutDark,
                                      height: 1.5),
                                  children: [
                                    const TextSpan(
                                        text: 'I have read and agree to the '),
                                    WidgetSpan(
                                      child: GestureDetector(
                                        onTap: _viewTerms,
                                        child: const Text(
                                          'Terms & Conditions',
                                          style: TextStyle(
                                            color: AppTheme.cutBlue,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const TextSpan(
                                        text:
                                            ' and Privacy Policy of the CUT Safety App.'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Warning shown if user tries to register without accepting
                    if (!_termsAccepted)
                      const Padding(
                        padding: EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          'You must accept the terms to continue.',
                          style:
                              TextStyle(fontSize: 11, color: AppTheme.cutRed),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Create Account button — disabled until terms accepted
                    ElevatedButton(
                      onPressed: (loading || !_termsAccepted) ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cutBlue,
                        disabledBackgroundColor: AppTheme.cutBorder,
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Create Account'),
                    ),
                    const SizedBox(height: 16),

                    // Sign in link
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('Already have an account? '),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Text('Sign In',
                            style: TextStyle(
                                color: AppTheme.cutBlue,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Read-only terms review screen (opened from the link) ─────────

class _TermsReviewScreen extends StatelessWidget {
  const _TermsReviewScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms & Conditions'),
        leading: const BackButton(),
      ),
      // Reuse the same TermsScreen content but without the accept flow —
      // the user just reads and presses Back to return to registration.
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: _TermsContentOnly(),
        ),
      ),
    );
  }
}

/// Standalone content widget so registration can embed it without
/// duplicating the full TermsScreen (which owns its own Scaffold).
class _TermsContentOnly extends StatelessWidget {
  const _TermsContentOnly();

  @override
  Widget build(BuildContext context) {
    // Import the same content sections defined in terms_screen.dart
    // by delegating to the exported widget.
    return const _TermsBody();
  }
}

/// Thin wrapper that re-uses _TermsContent from terms_screen.dart.
/// Because _TermsContent is private to that file we duplicate only
/// the rendered result here to keep files independent.
class _TermsBody extends StatelessWidget {
  const _TermsBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoBadge(),
        SizedBox(height: 20),
        _Clause(
          n: '1',
          title: 'Acceptance of Terms',
          body:
              'By creating an account on the CUT Safety App ("the App"), you confirm that you have read, understood, and agree to be bound by these Terms & Conditions. If you do not agree, you may not register or use the App.',
        ),
        _Clause(
          n: '2',
          title: 'Eligibility & Permitted Use',
          body:
              'The App is intended exclusively for registered students, staff, and authorised personnel of the Central University of Technology (CUT). Use is limited to reporting genuine safety incidents, community alerts, and related safety communications on or near CUT campuses. Any commercial, political, or unauthorised use is strictly prohibited.',
        ),
        _Clause(
          n: '3',
          title: 'SOS & Emergency Alerts',
          body:
              'The SOS feature is for genuine emergencies only. The App does not replace official emergency services — always dial 10111 (SAPS), 10177 (Ambulance), or 0514073911 (CUT Security) for life-threatening situations.\n\nDeliberate submission of false SOS alerts or fabricated incident reports may result in immediate account suspension and may constitute a criminal offence under South African law.',
        ),
        _Clause(
          n: '4',
          title: 'Location Data',
          body:
              'By using the App you consent to the collection and use of your real-time GPS location for displaying your position on the safety map, attaching location data to alerts and SOS events, and sharing approximate location with other verified App users during an active SOS.\n\nLocation data is stored securely in Firebase. You may revoke location permission at any time in your device settings.',
        ),
        _Clause(
          n: '5',
          title: 'User-Generated Content',
          body:
              'You are solely responsible for all content you post. You agree not to post content that is false, defamatory, threatening, discriminatory, or in violation of any applicable law. Administrators reserve the right to remove content and suspend accounts without notice.',
        ),
        _Clause(
          n: '6',
          title: 'Privacy & Data Protection',
          body:
              'Your personal data is stored securely using Google Firebase. We do not sell or share your information with third parties for commercial purposes. You may request deletion of your account and data by contacting the App administrator.',
        ),
        _Clause(
          n: '7',
          title: 'Limitation of Liability',
          body:
              'The App is provided on an "as-is" basis. We are not liable for any harm arising from reliance on user-posted information, App downtime, inaccurate location data, or delayed notifications. Users accept full responsibility for their own safety decisions.',
        ),
        _Clause(
          n: '8',
          title: 'Account Termination',
          body:
              'We reserve the right to suspend or permanently terminate any account that violates these Terms without prior notice, including for false emergency alerts, harassment, or hate speech.',
        ),
        _Clause(
          n: '9',
          title: 'Changes to These Terms',
          body:
              'These Terms may be updated from time to time. Continued use of the App after changes constitutes acceptance of the revised Terms.',
        ),
        _Clause(
          n: '10',
          title: 'Governing Law',
          body:
              'These Terms are governed by the laws of the Republic of South Africa. Any disputes shall be subject to the jurisdiction of the South African courts.',
        ),
        SizedBox(height: 8),
        Divider(),
        SizedBox(height: 8),
        Text(
          'For questions or concerns contact the CUT Safety App administrator via the CUT IT Helpdesk.',
          style: TextStyle(fontSize: 12, color: AppTheme.cutMuted, height: 1.5),
        ),
      ],
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.cutBlue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 14, color: AppTheme.cutBlue),
          SizedBox(width: 8),
          Text(
            'Last updated: April 2026',
            style: TextStyle(
                fontSize: 12,
                color: AppTheme.cutBlue,
                fontWeight: FontWeight.w600),
          ),
        ]),
      );
}

class _Clause extends StatelessWidget {
  final String n;
  final String title;
  final String body;
  const _Clause({required this.n, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(right: 10, top: 1),
              decoration: const BoxDecoration(
                  color: AppTheme.cutBlue, shape: BoxShape.circle),
              child: Center(
                child: Text(n,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.cutDark)),
            ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(body,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.cutDark, height: 1.6)),
          ),
        ]),
      );
}
