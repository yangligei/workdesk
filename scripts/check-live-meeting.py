#!/usr/bin/env python3
"""Real installed Hermes invocation; only synthetic meeting text leaves the host."""
import os
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
source = r'''
import Foundation
import WorkdeskCore
@main struct Check {
 static func main() async {
  do {
   let text = "小林：演示验证项目需要再跑一遍 demo。小周：我来整理演示验证的测试结果。小林：公众号运营的微信推文流程还需要梳理。"
   let prompt = try MeetingAnalysis.prompt(source: text, originalDate: "2026-11-04", projects: [
    ["id":"demo", "title":"演示验证", "tasks":""],
    ["id":"social", "title":"公众号运营", "tasks":""]
   ])
   let data = try await HermesMeetingAgent.analyze(prompt: prompt, directory: URL(fileURLWithPath: CommandLine.arguments[1]))
   let proposals = try MeetingAnalysis.decode(data, source: text, projects: ["demo", "social"], originalDate: "2026-11-04")
   guard proposals.contains(where: { $0.projectID == "demo" && $0.type == "task" }), proposals.contains(where: { $0.projectID == "social" && $0.type == "task" }) else { throw StoreError.database("missing expected project task proposals") }
   print("PASS real Hermes model -> strict JSON -> grounded evidence -> two project matches; \(proposals.count) proposals; no writes")
  } catch { print("FAIL real Hermes meeting: \(error)"); exit(1) }
 }
}
'''
with tempfile.TemporaryDirectory(prefix="workdesk-live-ai-", dir=os.environ["TMPDIR"]) as temporary:
    root = Path(temporary)
    (root / "Check.swift").write_text(source)
    build = repo / ".build/arm64-apple-macosx/debug"
    objects = [build / "WorkdeskCore.build" / (p.name + ".o") for p in sorted((repo / "Sources/WorkdeskCore").glob("*.swift"))]
    subprocess.run(["swiftc", "-parse-as-library", "-I", str(build), "-I", str(repo / "Sources/CSQLite"), str(root / "Check.swift"), *map(str, objects), "-o", str(root / "check")], check=True)
    subprocess.run([str(root / "check"), str(root)], check=True, timeout=150)
