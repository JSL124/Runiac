import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';

class RuniacAuthTitle extends StatelessWidget {
  const RuniacAuthTitle({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: RuniacColors.primaryBlue,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            color: RuniacColors.primaryBlue,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class RuniacHeroMark extends StatelessWidget {
  const RuniacHeroMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 340,
        height: 190,
        child: Semantics(
          label: 'Runiac logo',
          image: true,
          child: Image.asset(
            'assets/images/splash/runiac_splash_logo.png',
            key: const ValueKey('auth_welcome_runiac_logo'),
            width: 330,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class RuniacAuthTextField extends StatelessWidget {
  const RuniacAuthTextField({
    required this.label,
    required this.hintText,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    super.key,
  });

  final String label;
  final String hintText;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      enableSuggestions: !obscureText,
      autocorrect: !obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      validator: validator,
      style: const TextStyle(
        color: RuniacColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        suffixIcon: obscureText
            ? const Icon(
                Icons.visibility_outlined,
                color: RuniacColors.textSecondary,
              )
            : null,
        labelStyle: const TextStyle(
          color: RuniacColors.primaryBlue,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        hintStyle: TextStyle(
          color: RuniacColors.primaryBlue.withValues(alpha: 0.45),
          fontWeight: FontWeight.w600,
        ),
        errorStyle: const TextStyle(
          color: RuniacColors.accentOrange,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        filled: true,
        fillColor: RuniacColors.sectionSurfaceStrong,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: RuniacColors.cardBorder,
            width: 2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: RuniacColors.cardBorder,
            width: 2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: RuniacColors.primaryBlue,
            width: 2,
          ),
        ),
      ),
    );
  }
}

class RuniacAuthFeedback extends StatelessWidget {
  const RuniacAuthFeedback({
    required this.message,
    required this.isError,
    super.key,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      key: const ValueKey('auth_feedback_message'),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: isError ? RuniacColors.accentOrange : RuniacColors.primaryBlue,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        height: 1.35,
      ),
    );
  }
}
