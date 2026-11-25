"""Writes a main.swift that runs every test method of the given XCTestCase files."""
import re, sys
out = ["import Foundation", "@MainActor func runAll() {"]
for path in sys.argv[2:]:
    src = open(path).read()
    for cls in re.findall(r"final class (\w+): XCTestCase", src):
        body = src.split(f"class {cls}", 1)[1]
        for t in re.findall(r"\n    func (test\w+)\(\)( throws)?", body):
            name, throws = t
            call = f"try c.{name}()" if throws else f"c.{name}()"
            out.append(f'  do {{ xctCurrent = "{cls}.{name}"; let c = {cls}(); c.setUp(); try c.setUpWithError(); {call}; c.tearDown(); try c.tearDownWithError() }} catch {{ xctFail("threw \\(error)", #filePath, #line) }}')
out += ["}", "MainActor.assumeIsolated { runAll() }", 'print("failures: \\(xctFailures)")', "exit(xctFailures == 0 ? 0 : 1)"]
open(sys.argv[1], "w").write("\n".join(out))
