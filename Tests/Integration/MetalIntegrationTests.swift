import CLiteRT
import Darwin
import XCTest
@testable import LiteRTExample

private typealias GetNumAccelerators = @convention(c) (
  LiteRtEnvironment?,
  UnsafeMutablePointer<LiteRtParamIndex>?
) -> LiteRtStatus

private typealias GetAccelerator = @convention(c) (
  LiteRtEnvironment?,
  LiteRtParamIndex,
  UnsafeMutablePointer<LiteRtAccelerator?>?
) -> LiteRtStatus

private typealias GetAcceleratorHardwareSupport = @convention(c) (
  LiteRtAccelerator?,
  UnsafeMutablePointer<LiteRtHwAcceleratorSet>?
) -> LiteRtStatus

final class MetalRegistrationTests: XCTestCase {
  func testMetalAcceleratorRegistersWithLiteRT() throws {
    try LiteRTMetalRegistration.withRegisteredAccelerator { process in
      let environment = try createEnvironment()
      defer { LiteRtDestroyEnvironment(environment) }

      XCTAssertTrue(
        try hasRegisteredGPU(in: environment, process: process),
        "Metal accelerator was not registered"
      )
    }
  }
}

final class MetalInferenceTests: XCTestCase {
  func testAddModelRunsOnMetal() throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Metal inference requires a physical iOS device")
    #else
      try LiteRTMetalRegistration.withRegisteredAccelerator { _ in
        XCTAssertEqual(try LiteRTRunner.runOnMetal(), [3, 9])
      }
    #endif
  }
}

private func createEnvironment() throws -> LiteRtEnvironment {
  var environment: LiteRtEnvironment?
  try requireSuccess(
    LiteRtCreateEnvironment(0, nil, &environment),
    operation: "Create environment"
  )
  return try XCTUnwrap(environment)
}

private func hasRegisteredGPU(
  in environment: LiteRtEnvironment,
  process: UnsafeMutableRawPointer
) throws -> Bool {
  let getNumAccelerators = unsafeBitCast(
    try symbol("LiteRtGetNumAccelerators", in: process),
    to: GetNumAccelerators.self
  )
  let getAccelerator = unsafeBitCast(
    try symbol("LiteRtGetAccelerator", in: process),
    to: GetAccelerator.self
  )
  let getAcceleratorHardwareSupport = unsafeBitCast(
    try symbol("LiteRtGetAcceleratorHardwareSupport", in: process),
    to: GetAcceleratorHardwareSupport.self
  )

  var acceleratorCount: LiteRtParamIndex = 0
  try requireSuccess(
    getNumAccelerators(environment, &acceleratorCount),
    operation: "Get accelerator count"
  )

  let gpu = LiteRtHwAcceleratorSet(kLiteRtHwAcceleratorGpu.rawValue)
  for index in 0..<acceleratorCount {
    var accelerator: LiteRtAccelerator?
    try requireSuccess(
      getAccelerator(environment, index, &accelerator),
      operation: "Get accelerator"
    )
    let acceleratorHandle = try XCTUnwrap(accelerator)

    var hardware: LiteRtHwAcceleratorSet = 0
    try requireSuccess(
      getAcceleratorHardwareSupport(acceleratorHandle, &hardware),
      operation: "Get accelerator hardware support"
    )

    if hardware & gpu != 0 {
      return true
    }
  }

  return false
}

private func symbol(
  _ name: String,
  in process: UnsafeMutableRawPointer
) throws -> UnsafeMutableRawPointer {
  try XCTUnwrap(dlsym(process, name), "Missing symbol: \(name)")
}

private func requireSuccess(
  _ status: LiteRtStatus,
  operation: String
) throws {
  try XCTUnwrap(
    status == kLiteRtStatusOk ? status : nil,
    "\(operation) failed: \(status.rawValue)"
  )
}
