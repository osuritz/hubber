#!/usr/bin/env swift
// spike-probe.swift — Gate 1 standalone CLI probe
// Run with: swift Scripts/spike-probe.swift
// or:        swift Scripts/spike-probe.swift --write
//
// Prints whether containerURL(forSecurityApplicationGroupIdentifier:) returns
// a non-nil path for group.com.osuritz.hubber, then optionally writes/reads
// spike.json to prove a full round-trip.
//
// This runs as a plain CLI process (not sandboxed, no bundle), so it tells us
// what a NON-SANDBOXED host can do with the App Group entitlement.
// NOTE: without the entitlement actually embedded in a signed binary, macOS
// may still return nil — that's the exact Gate 1 question.

import Foundation

let appGroupID = "group.com.osuritz.hubber"
let spikeFileName = "spike.json"

print("=== Hubber Widget Spike — Gate 1 Probe ===")
print("App Group ID: \(appGroupID)")
print()

let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)

if let url = containerURL {
    print("[PASS] containerURL is NON-NIL: \(url.path)")
} else {
    print("[FAIL] containerURL is NIL — App Group not accessible under this signing context")
    print("       (This is the expected result for an unsigned/plain-swift-script process.)")
    print("       Run the same check from a codesigned binary with the entitlement to get the real answer.")
    exit(1)
}

// Optional write + read round-trip
let args = CommandLine.arguments
if args.contains("--write"), let url = containerURL {
    struct SpikePayload: Codable {
        var value: String
        var writtenAt: Double
    }

    let jsonURL = url.appendingPathComponent(spikeFileName)
    let payload = SpikePayload(value: "hello-from-probe", writtenAt: Date().timeIntervalSince1970)

    do {
        // Create the container directory if it doesn't exist yet
        // (on first run it may not be created by the OS)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: jsonURL, options: .atomic)
        print("[PASS] Wrote spike.json to: \(jsonURL.path)")

        // Immediate read-back
        let readData = try Data(contentsOf: jsonURL)
        let readBack = try JSONDecoder().decode(SpikePayload.self, from: readData)
        print("[PASS] Read back: value='\(readBack.value)' writtenAt=\(readBack.writtenAt)")
    } catch {
        print("[FAIL] Write/read failed: \(error)")
        exit(1)
    }
}

print()
print("Done. To test full round-trip: swift Scripts/spike-probe.swift --write")
