/// Invalid user input rejected by a repository; [message] is safe to show.
class ValidationException implements Exception {
  const ValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
