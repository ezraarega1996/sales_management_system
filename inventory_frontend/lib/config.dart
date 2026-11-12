/// Single source of truth for the backend address.
///
/// Override per build without editing code:
///   flutter run --dart-define=API_URL=https://api.example.com/api
///
/// The default is this computer's Wi-Fi IP, which only works for phones on the same network.
/// Use 'http://10.0.2.2:5000/api' for the Android emulator.
const String baseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://192.168.11.9:5000/api');
