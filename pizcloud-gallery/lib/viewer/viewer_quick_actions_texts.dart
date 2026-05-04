import 'package:flutter/foundation.dart';

@immutable
class ViewerQuickActionsTexts {
  const ViewerQuickActionsTexts({
    required this.quickActionsButtonLabel,
    required this.quickActionsSheetTitle,
    this.quickActionsSheetMessage,
    required this.shareLabel,
    required this.uploadLabel,
    required this.editLabel,
    required this.addToAlbumLabel,
    required this.deleteLabel,
    required this.cancelLabel,
  });

  const ViewerQuickActionsTexts.defaults()
    : quickActionsButtonLabel = 'Quick actions',
      quickActionsSheetTitle = 'Quick actions',
      quickActionsSheetMessage = 'Frequently used shortcuts',
      shareLabel = 'Share',
      uploadLabel = 'Upload',
      editLabel = 'Edit',
      addToAlbumLabel = 'Add to album',
      deleteLabel = 'Delete',
      cancelLabel = 'Cancel';

  final String quickActionsButtonLabel;
  final String quickActionsSheetTitle;
  final String? quickActionsSheetMessage;
  final String shareLabel;
  final String uploadLabel;
  final String editLabel;
  final String addToAlbumLabel;
  final String deleteLabel;
  final String cancelLabel;
}
