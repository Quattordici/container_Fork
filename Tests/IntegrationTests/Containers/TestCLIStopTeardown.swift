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

/// Verifies that stopping or force-deleting a container does not leak its
/// runtime service registration in launchd.
@Suite
struct TestCLIStopTeardown {
    private func launchdListing() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test func testStopDoesNotLeakRuntimeService() async throws {
        try await ContainerFixture.with { f in
            let image = WarmupImage.alpine320.rawValue
            try await f.withContainer(image: image, autoRemove: false) { name in
                #expect(try launchdListing().contains(name), "runtime service should be registered while running")
                try f.doStop(name, signal: "SIGKILL")
                #expect(try f.getContainerStatus(name) == "stopped")
                #expect(!(try launchdListing().contains(name)), "runtime service should be deregistered after stop")
            }
        }
    }

    @Test func testForceDeleteRunningDoesNotLeakRuntimeService() async throws {
        try await ContainerFixture.with { f in
            let image = WarmupImage.alpine320.rawValue
            try await f.withContainer(image: image) { name in
                try f.doRemove(name, force: true)
                let result = try f.run(["inspect", name])
                #expect(result.status != 0, "container should not exist after force delete")
                #expect(!(try launchdListing().contains(name)), "runtime service should be deregistered after force delete")
            }
        }
    }
}
