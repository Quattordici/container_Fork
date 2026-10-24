//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc. and the container project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import ContainerTestSupport
import Foundation
import Testing

@Suite
struct TestCLIStopHungRuntime {
    /// Returns the PIDs of the runtime helper processes serving `containerID`.
    private func runtimePIDs(for containerID: String) throws -> [pid_t] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pgrep")
        process.arguments = ["-f", "container-runtime-linux.*--uuid \(containerID)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.split(whereSeparator: \.isNewline).compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// A frozen runtime helper must not hang `container stop` forever, and the
    /// container must not be left stuck in the running state (apple/container#167).
    @Test func testStopReturnsWhenRuntimeIsHung() async throws {
        try await ContainerFixture.with { f in
            let image = WarmupImage.alpine320.rawValue
            try await f.withContainer(image: image, autoRemove: false) { name in
                let pids = try runtimePIDs(for: name)
                try #require(!pids.isEmpty, "could not find the runtime helper for \(name)")
                f.addCleanup {
                    for pid in pids { kill(pid, SIGCONT) }
                    try f.doRemoveIfExists(name, force: true, ignoreFailure: true)
                }

                for pid in pids { kill(pid, SIGSTOP) }

                // 1s stop timeout + the client's grace period; allow generous slack.
                let started = ContinuousClock.now
                _ = try f.run(["stop", "-t", "1", name])
                let elapsed = ContinuousClock.now - started
                #expect(elapsed < .seconds(150), "stop took \(elapsed); the XPC call is unbounded")

                // Whether or not stop reported an error, the container must have been torn down.
                try await f.retry(attempts: 10, delay: .seconds(2)) {
                    (try? f.getContainerStatus(name)) == "stopped"
                }
            }
        }
    }
}
