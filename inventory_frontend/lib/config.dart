/// Single source of truth for the backend address.
/// Every API call in the app (Api in utils/api.dart and BusinessService)
/// reads this value. Change it here to point the app at a different backend.
// 192.168.1.3 = this computer's Wi-Fi IP, so a phone on the same network
// can reach the backend. Use 'http://localhost:5000/api' for desktop/web,
// or 'http://10.0.2.2:5000/api' for the Android emulator.
const String baseUrl = 'http://192.168.1.3:5000/api';
