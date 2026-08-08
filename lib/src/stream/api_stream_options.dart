/// Controls a polling stream created via `SmartApiClient.stream(...)`.
///
/// The wait between calls is [interval] measured *after* the previous call
/// finishes, not a fixed wall-clock cadence — so the real gap between two
/// requests hitting the server is `interval + <time the call took>`, per
/// spec. A slow endpoint naturally polls less often; it never overlaps
/// itself.
class ApiStreamOptions {
  /// Delay after one call completes before the next one starts.
  final Duration interval;

  /// Fire the first call immediately on listen. If false, the stream waits
  /// [interval] before the very first call too.
  final bool immediate;

  const ApiStreamOptions({
    this.interval = const Duration(seconds: 10),
    this.immediate = true,
  });
}
