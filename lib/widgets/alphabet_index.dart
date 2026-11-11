import 'package:flutter/material.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

/// The strip of letters down the end edge of the list. Tap or drag over it
/// to jump to that letter; a bubble shows the letter under the finger.
class AlphabetIndex extends StatefulWidget {
  const AlphabetIndex({
    super.key,
    required this.letters,
    required this.onLetter,
  });

  final List<String> letters;
  final ValueChanged<String> onLetter;

  @override
  State<AlphabetIndex> createState() => _AlphabetIndexState();
}

class _AlphabetIndexState extends State<AlphabetIndex> {
  String? _active;

  void _pick(double dy, double height) {
    if (widget.letters.isEmpty || height <= 0) {
      return;
    }
    final int index = (dy / height * widget.letters.length).floor().clamp(
      0,
      widget.letters.length - 1,
    );
    final String letter = widget.letters[index];
    if (letter != _active) {
      setState(() => _active = letter);
      widget.onLetter(letter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Never taller than the letters need, never taller than the list.
        final double height = (widget.letters.length * 18.0).clamp(
          0.0,
          constraints.maxHeight,
        );
        final double slot = height / widget.letters.length;
        final int activeIndex = _active == null
            ? -1
            : widget.letters.indexOf(_active!);
        return Align(
          alignment: AlignmentDirectional.centerEnd,
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (activeIndex != -1)
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      top: (activeIndex * slot - 18).clamp(0.0, height),
                      end: 8,
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: colors.primary,
                      child: Text(
                        _active!,
                        style: TextStyle(
                          color: colors.onPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                Semantics(
                  label: context.l10n.jumpToALetter,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (TapDownDetails d) =>
                        _pick(d.localPosition.dy, height),
                    onTapUp: (_) => setState(() => _active = null),
                    onVerticalDragStart: (DragStartDetails d) =>
                        _pick(d.localPosition.dy, height),
                    onVerticalDragUpdate: (DragUpdateDetails d) =>
                        _pick(d.localPosition.dy, height),
                    onVerticalDragEnd: (_) => setState(() => _active = null),
                    onVerticalDragCancel: () => setState(() => _active = null),
                    child: SizedBox(
                      width: 24,
                      child: Column(
                        children: <Widget>[
                          for (final String letter in widget.letters)
                            SizedBox(
                              height: slot,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  letter,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: letter == _active
                                        ? colors.primary
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
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
      },
    );
  }
}
