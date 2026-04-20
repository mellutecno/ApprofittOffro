class AppLaunchTarget {
  final String type;
  final int? offerId;
  final int? otherUserId;
  final String? otherUserName;

  const AppLaunchTarget._(this.type, {this.offerId, this.otherUserId, this.otherUserName});

  static const login = AppLaunchTarget._('login');
  static const offers = AppLaunchTarget._('offers');
  static const profile = AppLaunchTarget._('profile');
  static const pendingRequests = AppLaunchTarget._('pendingRequests');
  static const chatRequest = AppLaunchTarget._('chatRequest');

  factory AppLaunchTarget.chat({
    required int offerId,
    required int otherUserId,
    required String otherUserName,
  }) {
    return AppLaunchTarget._(
      'chat',
      offerId: offerId,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
    );
  }

  bool get isChat => type == 'chat';
}
