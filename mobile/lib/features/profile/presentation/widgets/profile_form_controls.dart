import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../domain/repositories/user_profile_persistence_repository.dart';
import '../../domain/singapore_region_options.dart';

/// The profile form fields shared by onboarding and profile editing.
///
/// Shared so the same value is captured the same way in both places — date of
/// birth uses a Cupertino-style wheel rather than free text, and age is derived
/// and read-only rather than asked for, so it cannot disagree with the date.
///
/// Region is a fixed picker from the Singapore options list; leaderboard
/// standings are regional, so a free-text region would not be rankable.
class ProfileDateOfBirthField extends StatelessWidget {
  const ProfileDateOfBirthField({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = value.isEmpty ? 'Choose birthdate' : value;
    return Semantics(
      label: 'Date of birth',
      container: true,
      button: true,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showBirthdatePicker(context),
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Date of birth'),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  Future<void> _showBirthdatePicker(BuildContext context) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 100, now.month, now.day);
    final lastDate = DateTime(now.year - 13, now.month, now.day);
    var selectedDate = DateTime.tryParse(value) ?? DateTime(2000);
    if (selectedDate.isBefore(firstDate) || selectedDate.isAfter(lastDate)) {
      selectedDate = DateTime(2000);
    }

    final result = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: RuniacColors.white,
      builder: (context) {
        var pendingDate = selectedDate;
        return SafeArea(
          child: SizedBox(
            height: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Select birthdate',
                          style: TextStyle(
                            color: RuniacColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: selectedDate,
                    minimumDate: firstDate,
                    maximumDate: lastDate,
                    onDateTimeChanged: (value) {
                      pendingDate = value;
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(pendingDate),
                    child: const Text('Use selected date'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result != null) {
      onChanged(birthDateIso(result));
    }
  }
}

class ProfileAgeReadOnlyField extends StatelessWidget {
  const ProfileAgeReadOnlyField({required this.dateOfBirthIso, super.key});

  final String dateOfBirthIso;

  @override
  Widget build(BuildContext context) {
    final age = dateOfBirthIso.isEmpty
        ? 'Select birthdate first'
        : ageFromBirthDateIso(dateOfBirthIso).toString();
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Age'),
      child: Text(age),
    );
  }
}

class SingaporeRegionPickerField extends StatelessWidget {
  const SingaporeRegionPickerField({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Region',
      container: true,
      button: true,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showRegionPicker(context),
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Region'),
            child: Text(value.isEmpty ? 'Choose a Singapore region' : value),
          ),
        ),
      ),
    );
  }

  Future<void> _showRegionPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: RuniacColors.white,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Choose region',
                      style: TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      itemCount: SingaporeRegionOptions.values.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final region = SingaporeRegionOptions.values[index];
                        return ListTile(
                          title: Text(region),
                          trailing: region == value
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.of(context).pop(region),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    if (selected != null) {
      onChanged(selected);
    }
  }
}
