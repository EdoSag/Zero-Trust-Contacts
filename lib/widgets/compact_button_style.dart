import 'package:flutter/material.dart';

/// The shared Zero-Trust theme makes filled and outlined buttons full width
/// (one main action per screen). Buttons that sit in a row, a wrap or a list
/// tile use this to size to their label instead.
const ButtonStyle compactButtonStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll<Size>(Size(64, 40)),
);
