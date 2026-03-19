import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../shared/tts_service.dart';
import 'battery_service.dart';
import 'location_service.dart';

class SystemPage extends StatefulWidget {
  const SystemPage({super.key});

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {

  final BatteryService _battery = BatteryService();
  final LocationService _location = LocationService();

  bool _busy = false;

  Future<void> _speakBattery() async {
    if (_busy) return;
    _busy = true;

    try {
      final level = await _battery.getBatteryLevel();
      await TTSService.speak("Battery level is $level percent");
    } catch (e) {
      await TTSService.speak("Unable to get battery information");
    }

    _busy = false;
  }

  Future<void> _speakTime() async {
    if (_busy) return;
    _busy = true;

    final now = DateTime.now();
    final formatted = DateFormat('hh:mm a').format(now);
    await TTSService.speak("Current time is $formatted");

    _busy = false;
  }

  Future<void> _speakDate() async {
    if (_busy) return;
    _busy = true;

    final now = DateTime.now();
    final formatted = DateFormat('EEEE, MMMM d, yyyy').format(now);
    await TTSService.speak("Today is $formatted");

    _busy = false;
  }

  Future<void> _speakLocation() async {
    if (_busy) return;
    _busy = true;

    try {
      bool serviceEnabled =
      await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        await TTSService.speak("Location service is disabled");
        _busy = false;
        return;
      }

      LocationPermission permission =
      await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission =
        await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        await TTSService.speak(
            "Location permission permanently denied");
        _busy = false;
        return;
      }

      final position =
      await Geolocator.getCurrentPosition(
          desiredAccuracy:
          LocationAccuracy.high);

      final address =
      await _location.getAddressFromLatLng(
          position.latitude,
          position.longitude);

      await TTSService.speak("You are at $address");
    } catch (e) {
      await TTSService.speak("Unable to get location");
    }

    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("System Info"),
      ),
      body: Padding(
        padding:
        const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [

            _buildButton("Battery", _speakBattery),
            const SizedBox(height: 20),

            _buildButton("Time", _speakTime),
            const SizedBox(height: 20),

            _buildButton("Date", _speakDate),
            const SizedBox(height: 20),

            _buildButton("Location", _speakLocation),

          ],
        ),
      ),
    );
  }

  Widget _buildButton(
      String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
          BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 20,
              fontWeight:
              FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
