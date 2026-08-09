import 'package:flutter/material.dart';

class RuniacAuthScreenFrame extends StatelessWidget {
  const RuniacAuthScreenFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
            child: child,
          ),
        ),
      ),
    );
  }
}
