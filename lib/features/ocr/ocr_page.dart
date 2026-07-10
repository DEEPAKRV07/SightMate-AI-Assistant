// lib/features/ocr/ocr_page.dart
// OCR Screen Reader Page — updated to use upgraded OCRService façade
// No breaking API changes: existing processImage() signature retained.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../shared/camera_helper.dart';
import '../../shared/tts_service.dart';
import 'ocr_service.dart';

class OcrPage extends StatefulWidget {
  const OcrPage({super.key});

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  final _camera = CameraHelper();
  final _ocr    = OCRService();
  final _tts    = TTSService();

  bool   _ready       = false;
  bool   _scanning    = false;
  String _lastResult  = '';
  String _statusText  = 'Point camera at text and tap Scan';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _tts.init();
    await _camera.initialize();
    setState(() => _ready = true);
    await _tts.speak('Screen reader ready. Point at text and double tap to scan.');
  }

  @override
  void dispose() {
    _camera.dispose();
    _ocr.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning || !_ready) return;
    setState(() {
      _scanning   = true;
      _statusText = 'Scanning…';
    });

    try {
      final file = await _camera.takePicture();
      if (file == null) {
        setState(() => _statusText = 'Could not capture image.');
        return;
      }

      final inputImage = InputImage.fromFilePath(file.path);
      final result     = await _ocr.processImage(inputImage);

      if (result == null || result.isEmpty) {
        setState(() {
          _statusText = 'No text found.';
          _lastResult = '';
        });
        await _tts.speak('No text detected.');
      } else {
        setState(() {
          _lastResult = result;
          _statusText = 'Text found — reading aloud.';
        });
        await _tts.speak(result);
      }
    } finally {
      setState(() => _scanning = false);
      // Restart camera stream if needed
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_ready)
              Expanded(child: _buildCamera())
            else
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: Colors.cyanAccent),
                ),
              ),
            _buildResultPanel(),
            _buildScanButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: const Color(0xFF1A1A2E),
      child: Row(
        children: [
          const Icon(Icons.document_scanner, color: Color(0xFF00D4FF), size: 22),
          const SizedBox(width: 10),
          const Text(
            'Screen Reader',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.4)),
            ),
            child: const Text(
              'PaddleOCR v4',
              style: TextStyle(color: Color(0xFF00D4FF), fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    final controller = _camera.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('Camera unavailable', style: TextStyle(color: Colors.white54)));
    }
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: CameraPreview(controller),
    );
  }

  Widget _buildResultPanel() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minHeight: 80, maxHeight: 160),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _statusText,
            style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                _lastResult.isEmpty ? '—' : _lastResult,
                style: TextStyle(
                  color: _lastResult.isEmpty ? Colors.white24 : Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton() {
    return GestureDetector(
      onTap: _scan,
      onDoubleTap: _scan,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: _scanning
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF00D4FF), Color(0xFF0077AA)],
                ),
          color: _scanning ? Colors.white12 : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: _scanning ? [] : [
            BoxShadow(
              color: const Color(0xFF00D4FF).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: _scanning
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                    SizedBox(width: 12),
                    Text('Scanning…', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  ],
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.center_focus_strong, color: Colors.black, size: 22),
                    SizedBox(width: 10),
                    Text('Scan Text', style: TextStyle(
                      color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
        ),
      ),
    );
  }
}