class BrailleService {
  static final Map<String, String> _brailleMap = {
    "1": "a",
    "12": "b",
    "14": "c",
    "145": "d",
    "15": "e",
    "124": "f",
    "1245": "g",
    "125": "h",
    "24": "i",
    "245": "j",
    "13": "k",
    "123": "l",
    "134": "m",
    "1345": "n",
    "135": "o",
    "1234": "p",
    "12345": "q",
    "1235": "r",
    "234": "s",
    "2345": "t",
    "136": "u",
    "1236": "v",
    "2456": "w",
    "1346": "x",
    "13456": "y",
    "1356": "z"
  };

  static String convertDots(Set<int> dots) {
    List<int> sorted = dots.toList()..sort();

    String key = sorted.join();

    return _brailleMap[key] ?? "";
  }
}
