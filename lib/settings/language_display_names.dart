import 'app_settings.dart';

/// English display names for the translation targets. The Chinese names in
/// [languageNames] remain the canonical model-prompt names; this map is only
/// for the English UI.
const Map<String, String> _englishLanguageNames = {
  'zh': 'Chinese',
  'en': 'English',
  'ja': 'Japanese',
  'ko': 'Korean',
  'fr': 'French',
  'pt': 'Portuguese',
  'es': 'Spanish',
  'tr': 'Turkish',
  'ru': 'Russian',
  'ar': 'Arabic',
  'th': 'Thai',
  'it': 'Italian',
  'de': 'German',
  'vi': 'Vietnamese',
  'ms': 'Malay',
  'id': 'Indonesian',
  'tl': 'Filipino',
  'hi': 'Hindi',
  'zh-Hant': 'Traditional Chinese',
  'pl': 'Polish',
  'cs': 'Czech',
  'nl': 'Dutch',
  'km': 'Khmer',
  'my': 'Burmese',
  'fa': 'Persian',
  'gu': 'Gujarati',
  'ur': 'Urdu',
  'te': 'Telugu',
  'mr': 'Marathi',
  'he': 'Hebrew',
  'bn': 'Bengali',
  'ta': 'Tamil',
  'uk': 'Ukrainian',
  'bo': 'Tibetan',
  'kk': 'Kazakh',
  'mn': 'Mongolian',
  'ug': 'Uyghur',
  'yue': 'Cantonese',
};

String displayLanguageName(String code, {required bool english}) {
  if (english) return _englishLanguageNames[code] ?? code;
  return languageNames[code] ?? code;
}
