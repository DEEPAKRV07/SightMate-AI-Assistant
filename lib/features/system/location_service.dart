import 'package:geocoding/geocoding.dart';

class LocationService {
  Future<String> getAddressFromLatLng(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(latitude, longitude);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        return "${place.locality}, ${place.administrativeArea}, ${place.country}";
      }

      return "Unknown location";
    } catch (e) {
      return "Unable to determine address";
    }
  }
}
