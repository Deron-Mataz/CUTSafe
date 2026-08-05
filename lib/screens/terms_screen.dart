import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'auth/login_screen.dart';

/// Shown once to first-time users after the splash screen.
/// Sets [kTermsAcceptedKey] in SharedPreferences when accepted.
const String kTermsAcceptedKey = 'terms_accepted';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _accepted = false;
  bool _saving = false;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (!_accepted) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kTermsAcceptedKey, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cutBlue,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.shield_outlined,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'CUT Safety',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  const Text(
                    'Terms & Conditions',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Please read carefully before continuing',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          // ── Scrollable terms body ────────────────────────────────
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                        child: const _TermsContent(),
                      ),
                    ),
                  ),

                  // ── Accept checkbox + button ─────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border:
                          Border(top: BorderSide(color: AppTheme.cutBorder)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Checkbox row
                          InkWell(
                            onTap: () => setState(() => _accepted = !_accepted),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: _accepted,
                                      activeColor: AppTheme.cutBlue,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                      onChanged: (v) => setState(
                                          () => _accepted = v ?? false),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'I have read and agree to the Terms & Conditions and Privacy Policy of the CUT Safety App.',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.cutDark,
                                          height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Accept button
                          ElevatedButton(
                            onPressed: (_accepted && !_saving) ? _accept : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.cutBlue,
                              disabledBackgroundColor: AppTheme.cutBorder,
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Text('Accept & Continue',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Terms content ─────────────────────────────────────────────────

class _TermsContent extends StatelessWidget {
  const _TermsContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LastUpdated(),
        SizedBox(height: 20),
        _Section(
          number: '1',
          title: 'Acceptance of Terms',
          body:
              'By creating an account on the CUT Safety App ("the App"), you confirm that you have read, understood, and agree to be bound by these Terms & Conditions. If you do not agree, you may not register or use the App.',
        ),
        _Section(
          number: '2',
          title: 'Eligibility & Permitted Use',
          body:
              'The App is intended exclusively for registered students, staff, and authorised personnel of the Central University of Technology (CUT). Use of the App is limited to reporting genuine safety incidents, community alerts, and related safety communications on or near CUT campuses. Any commercial, political, or unauthorised use is strictly prohibited.',
        ),
        _Section(
          number: '3',
          title: 'SOS & Emergency Alerts',
          body:
              'The SOS feature is for genuine emergencies only. The App does not replace official emergency services — always dial 10111 (SAPS), 10177 (Ambulance), or 0514073911 (CUT Security) for life-threatening situations.\n\nDeliberate submission of false SOS alerts or fabricated incident reports may result in immediate account suspension and may constitute a criminal offence under South African law.',
        ),
        _Section(
          number: '4',
          title: 'Location Data',
          body:
              'By using the App you consent to the collection and use of your real-time GPS location for the following purposes:\n\n• Displaying your position on the safety map\n• Attaching location data to alerts and SOS events you create\n• Sharing approximate location with other verified App users during an active SOS\n\nLocation data is processed via Google Maps and stored securely in Firebase. You may revoke location permission at any time in your device settings, though this will limit App functionality.',
        ),
        _Section(
          number: '5',
          title: 'User-Generated Content',
          body:
              'You are solely responsible for all content you post, including alerts, updates, and group messages. You agree not to post content that is false, defamatory, threatening, discriminatory, or in violation of any applicable law. The App administrators reserve the right to remove content and suspend accounts without prior notice.',
        ),
        _Section(
          number: '6',
          title: 'Privacy & Data Protection',
          body:
              'Your personal data (name, email, campus, profile photo, and location) is stored securely using Google Firebase. We do not sell, rent, or share your personal information with third parties for commercial purposes. Data is retained for as long as your account is active. You may request deletion of your account and data by contacting the App administrator.',
        ),
        _Section(
          number: '7',
          title: 'Limitation of Liability',
          body:
              'The CUT Safety App and its developers provide this platform on an "as-is" basis. We do not guarantee uninterrupted or error-free operation. We are not liable for any harm, loss, or damage arising from:\n\n• Reliance on information posted by other users\n• Failure of the App to function in an emergency\n• Inaccurate location data\n• Delayed or missed notifications\n\nUsers accept full responsibility for their own safety decisions.',
        ),
        _Section(
          number: '8',
          title: 'Account Termination',
          body:
              'We reserve the right to suspend or permanently terminate any account that violates these Terms, without prior notice. Grounds for termination include, but are not limited to: false emergency alerts, harassment, hate speech, and repeated policy violations.',
        ),
        _Section(
          number: '9',
          title: 'Changes to These Terms',
          body:
              'These Terms may be updated from time to time. Continued use of the App after any changes constitutes acceptance of the revised Terms. Users will be notified of material changes via the App.',
        ),
        _Section(
          number: '10',
          title: 'Governing Law',
          body:
              'These Terms are governed by and construed in accordance with the laws of the Republic of South Africa. Any disputes arising from the use of this App shall be subject to the jurisdiction of the South African courts.',
        ),
        SizedBox(height: 8),
        Divider(),
        SizedBox(height: 8),
        Text(
          'For questions or concerns regarding these Terms, contact the CUT Safety App administrator via the CUT IT Helpdesk.',
          style: TextStyle(fontSize: 12, color: AppTheme.cutMuted, height: 1.5),
        ),
        SizedBox(height: 12),
      ],
    );
  }
}

class _LastUpdated extends StatelessWidget {
  const _LastUpdated();

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

class _Section extends StatelessWidget {
  final String number;
  final String title;
  final String body;

  const _Section({
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(right: 10, top: 1),
              decoration: const BoxDecoration(
                  color: AppTheme.cutBlue, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  number,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.cutDark),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(
              body,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.cutDark, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
