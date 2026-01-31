import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

class SearchDropdown<T> extends StatelessWidget {
  const SearchDropdown({
    super.key,
    required this.dropdownMenuEntries,
    required this.controller,
    this.onSelected,
    this.label,
    this.leadingIcon,
  });

  final List<DropdownMenuEntry<T>> dropdownMenuEntries;
  final TextEditingController controller;
  final void Function(T?)? onSelected;
  final Widget? label;
  final Widget? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final menuStyle = const MenuStyle(
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(15))),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return DropdownMenu(
          controller: controller,
          leadingIcon: leadingIcon,
          width: constraints.maxWidth,
          dropdownMenuEntries: dropdownMenuEntries,
          label: label,
          menuStyle: menuStyle,
          trailingIcon: Icon(
            context.platformIcon(material: Icons.arrow_drop_down_rounded, cupertino: CupertinoIcons.chevron_down),
          ),
          selectedTrailingIcon: Icon(
            context.platformIcon(material: Icons.arrow_drop_up_rounded, cupertino: CupertinoIcons.chevron_up),
          ),
          onSelected: onSelected,
        );
      },
    );
  }
}
