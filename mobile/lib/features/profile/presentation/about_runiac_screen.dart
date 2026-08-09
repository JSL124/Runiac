import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/legal/runiac_legal_link_launcher.dart';
import '../../../core/legal/runiac_legal_urls.dart';
import '../../../core/legal/runiac_url_opener.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';
import 'runiac_licenses_screen.dart';

/// Account → About Runiac. Shows the app identity, the running app
/// version/build, a short project description, and the built-in
/// open-source licenses page. Purely informational — reads no user data
/// and writes nothing to the backend.
class AboutRuniacScreen extends StatefulWidget {
  const AboutRuniacScreen({
    super.key,
    this.versionOverride,
    this.buildNumberOverride,
    this.legalUrlOpener = const UrlLauncherOpener(),
  });

  /// Seam so tests can observe the legal rows without launching a browser.
  final RuniacUrlOpener legalUrlOpener;

  /// When provided (together with [buildNumberOverride]), the screen skips
  /// the platform lookup and renders these values directly. Intended for
  /// tests, where a platform channel is not available.
  final String? versionOverride;

  /// See [versionOverride].
  final String? buildNumberOverride;

  @override
  State<AboutRuniacScreen> createState() => _AboutRuniacScreenState();
}

class _AboutRuniacScreenState extends State<AboutRuniacScreen> {
  String? _version;
  String? _buildNumber;

  @override
  void initState() {
    super.initState();
    final versionOverride = widget.versionOverride;
    final buildNumberOverride = widget.buildNumberOverride;
    if (versionOverride != null && buildNumberOverride != null) {
      _version = versionOverride;
      _buildNumber = buildNumberOverride;
    } else {
      _loadPackageInfo();
    }
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) {
      return;
    }
    setState(() {
      _version = info.version;
      _buildNumber = info.buildNumber;
    });
  }

  @override
  Widget build(BuildContext context) {
    final version = _version;
    final buildNumber = _buildNumber;
    final versionText = version == null || buildNumber == null
        ? 'Version —'
        : 'Version $version (build $buildNumber)';

    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'About Runiac',
              tooltip: 'Back to Account',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(overscroll: false),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AppIdentityCard(versionText: versionText),
                      const SizedBox(height: 16),
                      const _AboutProjectCard(),
                      const SizedBox(height: 16),
                      _LicensesRow(applicationVersion: version ?? ''),
                      const SizedBox(height: 12),
                      _LegalDocumentRow(
                        label: 'Terms of Service',
                        url: RuniacLegalUrls.terms,
                        opener: widget.legalUrlOpener,
                      ),
                      const SizedBox(height: 12),
                      _LegalDocumentRow(
                        label: 'Privacy Policy',
                        url: RuniacLegalUrls.privacy,
                        opener: widget.legalUrlOpener,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppIdentityCard extends StatelessWidget {
  const _AppIdentityCard({required this.versionText});

  final String versionText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Runiac',
            style: TextStyle(
              color: RuniacColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Built for new runners',
            style: TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            versionText,
            style: const TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutProjectCard extends StatelessWidget {
  const _AboutProjectCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ABOUT THIS PROJECT',
            style: TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Runiac is a beginner-focused running app built as a Final Year '
            'Project. It guides new runners through structured plans, tracks '
            'runs, and turns progress into simple, motivating feedback.',
            style: TextStyle(
              color: RuniacColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _LicensesRow extends StatelessWidget {
  const _LicensesRow({required this.applicationVersion});

  final String applicationVersion;

  @override
  Widget build(BuildContext context) {
    return RuniacTappableSurface(
      semanticLabel: 'Open-source licenses',
      borderRadius: BorderRadius.circular(18),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                RuniacLicensesScreen(applicationVersion: applicationVersion),
          ),
        );
      },
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Open-source licenses',
              style: TextStyle(
                color: RuniacColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
          ),
          SizedBox(width: 10),
          Icon(
            Icons.chevron_right_rounded,
            color: RuniacColors.textSecondary,
            size: 22,
          ),
        ],
      ),
    );
  }
}

/// Row that opens a hosted legal document in an in-app browser. Matches the
/// licenses row so the About list reads as one group.
class _LegalDocumentRow extends StatelessWidget {
  const _LegalDocumentRow({
    required this.label,
    required this.url,
    required this.opener,
  });

  final String label;
  final String url;
  final RuniacUrlOpener opener;

  @override
  Widget build(BuildContext context) {
    return RuniacTappableSurface(
      semanticLabel: label,
      borderRadius: BorderRadius.circular(18),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      onTap: () => openRuniacLegalUrl(context, opener: opener, url: url),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: RuniacColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.open_in_new_rounded,
            color: RuniacColors.textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }
}
