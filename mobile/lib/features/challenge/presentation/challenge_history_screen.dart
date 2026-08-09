import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../domain/challenge_copy.dart';
import '../domain/models/challenge_enums.dart';
import '../domain/models/challenge_history.dart';
import '../domain/repositories/challenge_repository.dart';
import 'challenge_ceremony_route.dart';
import 'challenge_result_screen.dart';
import 'widgets/challenge_badge_image.dart';
import 'widgets/challenge_widgets.dart';

/// The durable Challenge history surface, reached from the Explore header's
/// History action. Rows carry the tier badge thumbnail, title, completion date,
/// and a text-bearing outcome chip; tapping a row reopens the full result
/// screen for that entry. All values are backend-owned and read verbatim
/// through [ChallengeRepository.history].
class ChallengeHistoryScreen extends StatefulWidget {
  const ChallengeHistoryScreen({
    required this.repository,
    required this.onBack,
    super.key,
  });

  final ChallengeRepository repository;
  final VoidCallback onBack;

  @override
  State<ChallengeHistoryScreen> createState() => _ChallengeHistoryScreenState();
}

class _ChallengeHistoryScreenState extends State<ChallengeHistoryScreen> {
  List<ChallengeHistoryEntry>? _entries;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.repository.history();
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } on ChallengeFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = ChallengeCopy.failureMessage(failure.reason);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = ChallengeCopy.historyError;
      });
    }
  }

  Future<void> _openResult(ChallengeHistoryEntry entry) async {
    await Navigator.of(context).push(
      challengeCeremonyRoute<void>(
        builder: (context) => ChallengeResultScreen(
          result: entry.toResult(),
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: Column(
          children: [
            RuniacBackHeader(
              title: ChallengeCopy.historyTitle,
              onBack: widget.onBack,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const ChallengeLoadingState(label: ChallengeCopy.historyLoading);
    }
    final error = _error;
    if (error != null) {
      return ChallengeErrorState(message: error, onRetry: _load);
    }
    final entries = _entries ?? const <ChallengeHistoryEntry>[];
    if (entries.isEmpty) {
      return const ChallengeEmptyState(title: ChallengeCopy.historyEmpty);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: entries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _HistoryRow(entry: entry, onTap: () => _openResult(entry));
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.onTap});

  final ChallengeHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outcome = _historyOutcome(entry.outcome);
    return RuniacTappableSurface(
      key: ValueKey<String>('challenge-history-${entry.challengeId}'),
      onTap: onTap,
      semanticLabel:
          'Challenge ${challengeTierTitle(entry.tierId)}, ${outcome.label}',
      borderRadius: BorderRadius.circular(18),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.cardBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          ChallengeBadgeImage(
            tierId: entry.tierId,
            size: 46,
            dimmed: entry.outcome != ChallengeParticipantStatus.succeeded,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  challengeTierTitle(entry.tierId),
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(entry.endedAt),
                  style: const TextStyle(
                    color: RuniacColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ChallengeStatusChip(label: outcome.label, color: outcome.color),
        ],
      ),
    );
  }
}

class _HistoryOutcome {
  const _HistoryOutcome(this.label, this.color);

  final String label;
  final Color color;
}

_HistoryOutcome _historyOutcome(ChallengeParticipantStatus outcome) {
  return switch (outcome) {
    ChallengeParticipantStatus.succeeded =>
      const _HistoryOutcome(
        ChallengeCopy.outcomeBadgeEarned,
        RuniacColors.successGreen,
      ),
    ChallengeParticipantStatus.ineligible =>
      const _HistoryOutcome(
        ChallengeCopy.outcomeMinimumMissed,
        RuniacColors.textSecondary,
      ),
    ChallengeParticipantStatus.failed =>
      const _HistoryOutcome(
        ChallengeCopy.outcomeFailed,
        RuniacColors.textSecondary,
      ),
    ChallengeParticipantStatus.cancelled =>
      const _HistoryOutcome(
        ChallengeCopy.outcomeCancelled,
        RuniacColors.textSecondary,
      ),
    ChallengeParticipantStatus.left =>
      const _HistoryOutcome(
        ChallengeCopy.outcomeLeft,
        RuniacColors.textSecondary,
      ),
    ChallengeParticipantStatus.accepted ||
    ChallengeParticipantStatus.active =>
      const _HistoryOutcome(
        ChallengeCopy.outcomeCancelled,
        RuniacColors.textSecondary,
      ),
  };
}

const List<String> _monthAbbreviations = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) {
  final month = _monthAbbreviations[date.month - 1];
  return '${date.day} $month ${date.year}';
}
