# SightMate – AI Assistant for the Visually Impaired

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat-square&logo=dart&logoColor=white)
![TensorFlow Lite](https://img.shields.io/badge/TensorFlow%20Lite-FF6F00?style=flat-square&logo=tensorflow&logoColor=white)
![YOLOv8](https://img.shields.io/badge/YOLOv8-Computer%20Vision-00A67E?style=flat-square)
![Android](https://img.shields.io/badge/Android-3DDC84?style=flat-square&logo=android&logoColor=white)

SightMate is an AI-powered mobile assistant designed to help visually impaired users navigate and interact with their surroundings using real-time computer vision and voice feedback.

---

## 🚀 Features

- 🎯 Real-time Object Detection (YOLOv8 TFLite)
- 🧭 Smart Navigation using Segmentation + Fusion
- 📖 OCR (Text Reading using ML Kit)
- 🎙️ Voice Assistant (Command-based interaction)
- ⠿ Braille Keyboard Input
- 🌍 Language Translation
- 🔋 System Info (Battery, Time, Location)

---

## 🧠 How It Works

Camera → YOLO Detection → Segmentation → Fusion Logic → Voice Feedback

---

## 🛠️ Tech Stack

- Flutter (UI + App)
- TensorFlow Lite (AI Models)
- YOLOv8 (Object Detection)
- Google ML Kit (OCR)
- Dart (Core Logic)

---

## 📂 Project Structure

lib/  
├── core/  
├── features/  
│ ├── object_detection/  
│ ├── navigation/  
│ ├── ocr/  
│ ├── assistant/  
│ ├── braille/  
│ ├── system/  
│ ├── translation/  


---

## 📈 Project Evolution

- Phase 1: Basic Blind Assistance System
- Phase 2: Added OCR and Voice
- Phase 3 (Current): Full AI Assistant with Navigation + Braille + YOLO

---

## ⚙️ Setup Instructions

1. Clone the repository: git clone https://github.com/DEEPAKRV07/SightMate-AI-Assistant.git
2. Navigate to project: cd SightMate-AI-Assistant
3. Install dependencies: flutter pub get
4. Run the app: flutter run

---

## 💡 Future Improvements

- GPS Navigation (Outdoor mode)
- Depth Estimation for distance awareness
- AI Chat Integration (Gemini / ChatGPT)
- Emergency SOS feature

---

## Accessibility and limitations

SightMate is an assistive technology prototype, not a replacement for a white cane, guide dog, or professional mobility training. Detection and navigation guidance can be affected by lighting, camera positioning, obstacles, and model limitations.

---

## 👨‍💻 Authors

Deepak R.V  
Gowtham S  
Harmithaa V  
