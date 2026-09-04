import 'dart:io';

void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/check_coverage.dart <lcov-file> [minimum-percent]',
    );
    exitCode = 64;
    return;
  }

  final File coverageFile = File(arguments.first);
  final double minimum = arguments.length == 2
      ? double.parse(arguments[1])
      : 17.5;
  if (!coverageFile.existsSync()) {
    stderr.writeln('Coverage file not found: ${coverageFile.path}');
    exitCode = 66;
    return;
  }

  int linesFound = 0;
  int linesHit = 0;
  for (final String line in coverageFile.readAsLinesSync()) {
    if (line.startsWith('LF:')) {
      linesFound += int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      linesHit += int.parse(line.substring(3));
    }
  }

  if (linesFound == 0) {
    stderr.writeln('Coverage report contains no executable lines.');
    exitCode = 65;
    return;
  }

  final double percentage = linesHit * 100 / linesFound;
  stdout.writeln(
    'Line coverage: ${percentage.toStringAsFixed(2)}% '
    '($linesHit/$linesFound), minimum ${minimum.toStringAsFixed(2)}%',
  );
  if (percentage + 0.000001 < minimum) {
    stderr.writeln('Coverage is below the required minimum.');
    exitCode = 1;
  }
}
