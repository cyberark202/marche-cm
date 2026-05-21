class AuthState {
  final bool isAuthenticated;
  final bool isOnboarded;
  final int? userId;
  final String? username;
  final bool isLoading;

  const AuthState({
    this.isAuthenticated = false,
    this.isOnboarded = false,
    this.userId,
    this.username,
    this.isLoading = true,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isOnboarded,
    int? userId,
    String? username,
    bool? isLoading,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isOnboarded: isOnboarded ?? this.isOnboarded,
        userId: userId ?? this.userId,
        username: username ?? this.username,
        isLoading: isLoading ?? this.isLoading,
      );
}
