class KalmanFilter {
  final double processNoise;
  final double measurementNoise;
  double _estimate;
  double _error;

  KalmanFilter({
    this.processNoise = 1.0,
    this.measurementNoise = 1.0,
    double initialEstimate = 0.0,
    double initialError = 1.0,
  })  : _estimate = initialEstimate,
        _error = initialError;

  double estimate(double prev, double meas) {
    // Predict
    _estimate = prev;
    _error += processNoise;

    // Update
    double kalmanGain = _error / (_error + measurementNoise);
    _estimate = _estimate + kalmanGain * (meas - _estimate);
    _error = (1 - kalmanGain) * _error;

    return _estimate;
  }

  void reset({double estimate = 0.0, double error = 1.0}) {
    _estimate = estimate;
    _error = error;
  }

  double get currentEstimate => _estimate;
  double get currentError => _error;
}