String? validateRuniacAuthEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) {
    return 'Enter your email';
  }

  final hasValidShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  if (!hasValidShape) {
    return 'Enter a valid email';
  }

  return null;
}

String? validateRuniacRequiredPassword(String? value) {
  if ((value ?? '').isEmpty) {
    return 'Password is required';
  }

  return null;
}

String? validateRuniacNewPassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) {
    return 'Password is required';
  }

  if (password.length < 8) {
    return 'Use at least 8 characters';
  }

  return null;
}
