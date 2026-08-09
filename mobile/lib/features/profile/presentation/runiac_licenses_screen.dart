import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';

/// Runiac-styled replacement for Flutter's built-in `showLicensePage`.
///
/// Aggregates every [LicenseEntry] published to [LicenseRegistry] by package
/// name (mirroring the aggregation Flutter's own `LicensePage` performs
/// internally) and renders the list, and each package's license text, with
/// the same header/card/footer visual language used across Account screens.
class RuniacLicensesScreen extends StatefulWidget {
  const RuniacLicensesScreen({this.applicationVersion = '', super.key});

  /// Shown in the footer as `Version {applicationVersion}` when non-empty.
  final String applicationVersion;

  @override
  State<RuniacLicensesScreen> createState() => _RuniacLicensesScreenState();
}

class _RuniacLicensesScreenState extends State<RuniacLicensesScreen> {
  bool _loading = true;
  Map<String, List<LicenseEntry>> _entriesByPackage =
      <String, List<LicenseEntry>>{};
  List<String> _packageNames = <String>[];

  @override
  void initState() {
    super.initState();
    _loadLicenses();
  }

  Future<void> _loadLicenses() async {
    final byPackage = <String, List<LicenseEntry>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        byPackage.putIfAbsent(package, () => <LicenseEntry>[]).add(entry);
      }
    }
    if (!mounted) {
      return;
    }
    final names = byPackage.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    setState(() {
      _entriesByPackage = byPackage;
      _packageNames = names;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'Open-source licenses',
              tooltip: 'Back to About',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(overscroll: false),
                child: _loading
                    ? const _LicensesLoadingState()
                    : SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_packageNames.isEmpty)
                              const _NoLicensesCard()
                            else
                              _LicensesListCard(
                                packageNames: _packageNames,
                                entriesByPackage: _entriesByPackage,
                              ),
                            const SizedBox(height: 20),
                            _LicensesFooter(
                              applicationVersion: widget.applicationVersion,
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

class _LicensesLoadingState extends StatelessWidget {
  const _LicensesLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 12),
          Text(
            'Loading licenses…',
            style: TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoLicensesCard extends StatelessWidget {
  const _NoLicensesCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.sectionSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RuniacColors.cardBorder),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Text(
          'No open-source licenses were found.',
          style: TextStyle(
            color: RuniacColors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

class _LicensesListCard extends StatelessWidget {
  const _LicensesListCard({
    required this.packageNames,
    required this.entriesByPackage,
  });

  final List<String> packageNames;
  final Map<String, List<LicenseEntry>> entriesByPackage;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Column(
        children: [
          for (var index = 0; index < packageNames.length; index++) ...[
            _LicensePackageRow(
              packageName: packageNames[index],
              entries: entriesByPackage[packageNames[index]]!,
            ),
            if (index != packageNames.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: RuniacColors.border,
                indent: 58,
              ),
          ],
        ],
      ),
    );
  }
}

class _LicensePackageRow extends StatelessWidget {
  const _LicensePackageRow({required this.packageName, required this.entries});

  final String packageName;
  final List<LicenseEntry> entries;

  @override
  Widget build(BuildContext context) {
    final licenseCount = entries.length;
    final subtitle = licenseCount == 1 ? '1 license' : '$licenseCount licenses';
    return RuniacTappableSurface(
      semanticLabel: packageName,
      borderRadius: BorderRadius.zero,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _RuniacLicenseDetailScreen(
              packageName: packageName,
              entries: entries,
            ),
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _IconTile(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: RuniacColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.chevron_right_rounded,
            color: RuniacColors.textSecondary,
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: RuniacColors.sectionSurfaceStrong,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.article_outlined,
        color: RuniacColors.primaryBlue,
        size: 18,
      ),
    );
  }
}

class _LicensesFooter extends StatelessWidget {
  const _LicensesFooter({required this.applicationVersion});

  final String applicationVersion;

  @override
  Widget build(BuildContext context) {
    final versionLine = applicationVersion.isEmpty
        ? null
        : 'Version $applicationVersion';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Runiac',
            style: TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (versionLine != null) ...[
            const SizedBox(height: 2),
            Text(
              versionLine,
              style: const TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Built with open-source software. Thank you to the maintainers.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders every [LicenseParagraph] contributed by every [LicenseEntry] for
/// a single package, in order — the same content Flutter's own
/// `LicensePage` detail view shows, styled for Runiac.
class _RuniacLicenseDetailScreen extends StatelessWidget {
  const _RuniacLicenseDetailScreen({
    required this.packageName,
    required this.entries,
  });

  final String packageName;
  final List<LicenseEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: packageName,
              tooltip: 'Back to licenses',
              titleMaxLines: 1,
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
                      for (var index = 0; index < entries.length; index++) ...[
                        _LicenseEntryBody(entry: entries[index]),
                        if (index != entries.length - 1) ...[
                          const SizedBox(height: 16),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: RuniacColors.border,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
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

class _LicenseEntryBody extends StatelessWidget {
  const _LicenseEntryBody({required this.entry});

  final LicenseEntry entry;

  @override
  Widget build(BuildContext context) {
    final paragraphs = entry.paragraphs.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final paragraph in paragraphs)
          _LicenseParagraphText(paragraph: paragraph),
      ],
    );
  }
}

class _LicenseParagraphText extends StatelessWidget {
  const _LicenseParagraphText({required this.paragraph});

  final LicenseParagraph paragraph;

  @override
  Widget build(BuildContext context) {
    final isCentered = paragraph.indent == LicenseParagraph.centeredIndent;
    if (isCentered) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          paragraph.text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: RuniacColors.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            height: 1.35,
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: 8, left: paragraph.indent * 12.0),
      child: Text(
        paragraph.text,
        style: const TextStyle(
          color: RuniacColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
      ),
    );
  }
}
