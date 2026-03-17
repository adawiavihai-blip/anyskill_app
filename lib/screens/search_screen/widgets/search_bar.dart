import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart'; // ignore: unused_import — partial i18n pass

class CustomSearchBar extends StatefulWidget {
  final Function(String)? onChanged;

  const CustomSearchBar({super.key, this.onChanged});

  @override
  State<CustomSearchBar> createState() => _CustomSearchBarState();
}

class _CustomSearchBarState extends State<CustomSearchBar>
    with SingleTickerProviderStateMixin {
  // --- אנימציית כניסה ---
  late final AnimationController _entryController;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  // --- אפקט פוקוס ---
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnim = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    ));

    _entryController.forward();

    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: _isFocused
                    ? Colors.pinkAccent.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: _isFocused ? 28 : 20,
                spreadRadius: _isFocused ? 2 : 0,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: _isFocused
                  ? Colors.pinkAccent.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: TextField(
            focusNode: _focusNode,
            onChanged: widget.onChanged,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: "מה בא לך לעשות היום?",
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              prefixIcon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  Icons.search,
                  key: ValueKey(_isFocused),
                  color: _isFocused ? Colors.pinkAccent : Colors.grey,
                  size: 24,
                ),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ),
    );
  }
}
