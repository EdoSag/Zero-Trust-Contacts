import 'package:flutter/material.dart';

/// The direction a piece of text reads in, from its first strong character:
/// right-to-left for Hebrew and Arabic, left-to-right otherwise. Null when
/// the text has no letters (numbers, symbols, empty), so the caller keeps
/// the direction of the screen.
TextDirection? directionOf(String text) {
  for (final int rune in text.runes) {
    if (_isRtl(rune)) {
      return TextDirection.rtl;
    }
    if (_isLtrLetter(rune)) {
      return TextDirection.ltr;
    }
  }
  return null;
}

bool _isRtl(int rune) =>
    (rune >= 0x0590 && rune <= 0x08FF) || // Hebrew, Arabic, Syriac, Thaana…
    (rune >= 0xFB1D && rune <= 0xFDFF) || // Hebrew and Arabic presentation
    (rune >= 0xFE70 && rune <= 0xFEFF);

bool _isLtrLetter(int rune) =>
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune >= 0x61 && rune <= 0x7A) ||
    (rune >= 0xC0 && rune <= 0x058F) ||
    (rune >= 0x0900 && rune <= 0xD7FF);

/// A text field that follows the direction of what is typed into it, so a
/// Hebrew name reads right-to-left on an English screen and the other way
/// round.
class DirectionalTextField extends StatefulWidget {
  const DirectionalTextField({
    super.key,
    required this.controller,
    this.decoration,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.forceLtr = false,
    this.readOnly = false,
    this.onTap,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLines;

  /// Phone numbers and email addresses always read left-to-right.
  final bool forceLtr;
  final bool readOnly;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  State<DirectionalTextField> createState() => _DirectionalTextFieldState();
}

class _DirectionalTextFieldState extends State<DirectionalTextField> {
  TextDirection? _direction;

  @override
  void initState() {
    super.initState();
    _direction = directionOf(widget.controller.text);
    widget.controller.addListener(_update);
  }

  @override
  void didUpdateWidget(DirectionalTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
      _direction = directionOf(widget.controller.text);
    }
  }

  void _update() {
    final TextDirection? next = directionOf(widget.controller.text);
    if (next != _direction && mounted) {
      setState(() => _direction = next);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextDirection ambient = Directionality.of(context);
    final TextDirection direction = widget.forceLtr
        ? TextDirection.ltr
        : (_direction ?? ambient);
    return TextField(
      controller: widget.controller,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization,
      maxLines: widget.maxLines,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      autofocus: widget.autofocus,
      textDirection: direction,
      // Keep the text on the side the screen starts from when it is forced
      // left-to-right (a phone number on a Hebrew screen).
      textAlign: widget.forceLtr && ambient == TextDirection.rtl
          ? TextAlign.end
          : TextAlign.start,
    );
  }
}
