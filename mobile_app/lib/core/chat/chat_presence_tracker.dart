class ChatPresenceTracker {
  static int? _activeOfferId;
  static int? _activeOtherUserId;

  static void setActiveConversation({
    required int offerId,
    required int otherUserId,
  }) {
    _activeOfferId = offerId;
    _activeOtherUserId = otherUserId;
  }

  static void clearConversation({
    required int offerId,
    required int otherUserId,
  }) {
    if (_activeOfferId == offerId && _activeOtherUserId == otherUserId) {
      _activeOfferId = null;
      _activeOtherUserId = null;
    }
  }

  static bool isViewingConversation({
    required int offerId,
    required int otherUserId,
  }) {
    return _activeOfferId == offerId && _activeOtherUserId == otherUserId;
  }
}
