/// log.dart – Zentraler Logger-Wrapper. In lib/ nie print verwenden.
library;

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

final Logger log = Logger(
  level: kDebugMode ? Level.debug : Level.warning,
  printer: SimplePrinter(colors: false),
);
