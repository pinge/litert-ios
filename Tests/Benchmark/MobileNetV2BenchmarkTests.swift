import CLiteRT
import Dispatch
import Foundation
import XCTest

final class MobileNetV2BenchmarkTests: XCTestCase {
  func testCPU() throws {
    try validate(
      benchmark(
        accelerator: "cpu",
        hardwareAccelerators: LiteRtHwAcceleratorSet(kLiteRtHwAcceleratorCpu.rawValue)
      )
    )
  }

  func testMetal() throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Metal benchmark requires a physical iOS device")
    #else
      try LiteRTMetalRegistration.withRegisteredAccelerator { _ in
        try validate(
          benchmark(
            accelerator: "metal",
            hardwareAccelerators: LiteRtHwAcceleratorSet(kLiteRtHwAcceleratorGpu.rawValue)
          )
        )
      }
    #endif
  }

  private func benchmark(
    accelerator: String,
    hardwareAccelerators: LiteRtHwAcceleratorSet
  ) throws -> BenchmarkResult {
    let modelURL = try XCTUnwrap(
      Bundle(for: MobileNetV2BenchmarkTests.self).url(
        forResource: "mobilenet_v2_1.0_224",
        withExtension: "tflite"
      )
    )
    let modelData = try Data(contentsOf: modelURL)

    var environment: LiteRtEnvironment?
    try requireSuccess(
      LiteRtCreateEnvironment(0, nil, &environment),
      operation: "Create environment"
    )
    let environmentHandle = try XCTUnwrap(environment)
    defer { LiteRtDestroyEnvironment(environmentHandle) }

    return try modelData.withUnsafeBytes { modelBytes in
      try benchmark(
        accelerator: accelerator,
        hardwareAccelerators: hardwareAccelerators,
        environment: environmentHandle,
        modelBytes: modelBytes
      )
    }
  }

  private func benchmark(
    accelerator: String,
    hardwareAccelerators: LiteRtHwAcceleratorSet,
    environment: LiteRtEnvironment,
    modelBytes: UnsafeRawBufferPointer
  ) throws -> BenchmarkResult {
    let modelAddress = try XCTUnwrap(modelBytes.baseAddress)
    var model: LiteRtModel?
    try requireSuccess(
      LiteRtCreateModelFromBuffer(
        environment,
        modelAddress,
        modelBytes.count,
        &model
      ),
      operation: "Create model"
    )
    let modelHandle = try XCTUnwrap(model)
    defer { LiteRtDestroyModel(modelHandle) }

    var options: LiteRtOptions?
    try requireSuccess(LiteRtCreateOptions(&options), operation: "Create options")
    let optionsHandle = try XCTUnwrap(options)
    defer { LiteRtDestroyOptions(optionsHandle) }

    try requireSuccess(
      LiteRtSetOptionsHardwareAccelerators(optionsHandle, hardwareAccelerators),
      operation: "Select hardware accelerator"
    )

    let compileStart = DispatchTime.now().uptimeNanoseconds
    var compiledModel: LiteRtCompiledModel?
    try requireSuccess(
      LiteRtCreateCompiledModel(environment, modelHandle, optionsHandle, &compiledModel),
      operation: "Compile model"
    )
    let compileDuration = duration(since: compileStart)
    let compiledModelHandle = try XCTUnwrap(compiledModel)
    defer { LiteRtDestroyCompiledModel(compiledModelHandle) }

    return try benchmark(
      accelerator: accelerator,
      environment: environment,
      model: modelHandle,
      compiledModel: compiledModelHandle,
      compileDuration: compileDuration
    )
  }

  private func benchmark(
    accelerator: String,
    environment: LiteRtEnvironment,
    model: LiteRtModel,
    compiledModel: LiteRtCompiledModel,
    compileDuration: Double
  ) throws -> BenchmarkResult {
    var signature: LiteRtSignature?
    try requireSuccess(
      LiteRtGetModelSignature(model, 0, &signature),
      operation: "Get model signature"
    )
    let signatureHandle = try XCTUnwrap(signature)

    let inputType = try rankedTensorType(signature: signatureHandle, input: true)
    let outputType = try rankedTensorType(signature: signatureHandle, input: false)
    guard
      inputType.element_type == kLiteRtElementTypeFloat32,
      outputType.element_type == kLiteRtElementTypeFloat32
    else {
      throw BenchmarkError.requiresFloat32Tensors
    }

    let inputBufferHandle = try createBuffer(
      environment: environment,
      compiledModel: compiledModel,
      tensorType: inputType,
      input: true
    )
    defer { LiteRtDestroyTensorBuffer(inputBufferHandle) }

    let outputBufferHandle = try createBuffer(
      environment: environment,
      compiledModel: compiledModel,
      tensorType: outputType,
      input: false
    )
    defer { LiteRtDestroyTensorBuffer(outputBufferHandle) }

    try clear(inputBufferHandle)
    try invoke(compiledModel, input: inputBufferHandle, output: outputBufferHandle)

    var inferenceDurations: [Double] = []
    for _ in 0..<10 {
      let start = DispatchTime.now().uptimeNanoseconds
      try invoke(compiledModel, input: inputBufferHandle, output: outputBufferHandle)
      inferenceDurations.append(duration(since: start))
    }

    return BenchmarkResult(
      accelerator: accelerator,
      compileDuration: compileDuration,
      inferenceDurations: inferenceDurations,
      output: try readFloat32(outputBufferHandle)
    )
  }

  private func createBuffer(
    environment: LiteRtEnvironment,
    compiledModel: LiteRtCompiledModel,
    tensorType: LiteRtRankedTensorType,
    input: Bool
  ) throws -> LiteRtTensorBuffer {
    var requirements: LiteRtTensorBufferRequirements?
    let requirementsStatus = input
      ? LiteRtGetCompiledModelInputBufferRequirements(compiledModel, 0, 0, &requirements)
      : LiteRtGetCompiledModelOutputBufferRequirements(compiledModel, 0, 0, &requirements)
    try requireSuccess(
      requirementsStatus,
      operation: input ? "Get input buffer requirements" : "Get output buffer requirements"
    )

    var mutableTensorType = tensorType
    var buffer: LiteRtTensorBuffer?
    try requireSuccess(
      LiteRtCreateManagedTensorBufferFromRequirements(
        environment,
        &mutableTensorType,
        try XCTUnwrap(requirements),
        &buffer
      ),
      operation: input ? "Create input buffer" : "Create output buffer"
    )
    return try XCTUnwrap(buffer)
  }

  private func validate(_ result: BenchmarkResult) throws {
    XCTAssertEqual(result.inferenceDurations.count, 10)
    XCTAssertFalse(result.output.isEmpty)
    XCTAssertTrue(result.output.allSatisfy { $0.isFinite })

    let report: [String: Any] = [
      "accelerator": result.accelerator,
      "compile": result.compileDuration,
      "inference_average": result.averageDuration,
      "inference_max": try XCTUnwrap(result.inferenceDurations.max()),
      "inference_min": try XCTUnwrap(result.inferenceDurations.min()),
      "measured_runs": result.inferenceDurations.count,
      "output_elements": result.output.count,
      "warmup_runs": 1
    ]
    let reportData = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    print("LITERT_BENCHMARK \(try XCTUnwrap(String(data: reportData, encoding: .utf8)))")
  }
}

private struct BenchmarkResult {
  let accelerator: String
  let compileDuration: Double
  let inferenceDurations: [Double]
  let output: [Float]

  var averageDuration: Double {
    inferenceDurations.reduce(0, +) / Double(inferenceDurations.count)
  }
}

private func rankedTensorType(
  signature: LiteRtSignature,
  input: Bool
) throws -> LiteRtRankedTensorType {
  var tensor: LiteRtTensor?
  let status = input
    ? LiteRtGetSignatureInputTensorByIndex(signature, 0, &tensor)
    : LiteRtGetSignatureOutputTensorByIndex(signature, 0, &tensor)
  try requireSuccess(status, operation: input ? "Get input tensor" : "Get output tensor")

  var tensorType = LiteRtRankedTensorType()
  try requireSuccess(
    LiteRtGetRankedTensorType(try XCTUnwrap(tensor), &tensorType),
    operation: input ? "Get input tensor type" : "Get output tensor type"
  )
  return tensorType
}

private func clear(_ buffer: LiteRtTensorBuffer) throws {
  var size = 0
  try requireSuccess(
    LiteRtGetTensorBufferPackedSize(buffer, &size),
    operation: "Get input buffer size"
  )

  var address: UnsafeMutableRawPointer?
  try requireSuccess(
    LiteRtLockTensorBuffer(buffer, &address, kLiteRtTensorBufferLockModeWrite),
    operation: "Lock input buffer"
  )
  memset(try XCTUnwrap(address), 0, size)
  try requireSuccess(LiteRtUnlockTensorBuffer(buffer), operation: "Unlock input buffer")
}

private func invoke(
  _ compiledModel: LiteRtCompiledModel,
  input: LiteRtTensorBuffer,
  output: LiteRtTensorBuffer
) throws {
  var inputs: [LiteRtTensorBuffer?] = [input]
  var outputs: [LiteRtTensorBuffer?] = [output]
  let status = inputs.withUnsafeMutableBufferPointer { inputPointer in
    outputs.withUnsafeMutableBufferPointer { outputPointer in
      LiteRtRunCompiledModel(
        compiledModel,
        0,
        inputPointer.count,
        inputPointer.baseAddress,
        outputPointer.count,
        outputPointer.baseAddress
      )
    }
  }
  try requireSuccess(status, operation: "Run model")
}

private func readFloat32(_ buffer: LiteRtTensorBuffer) throws -> [Float] {
  var size = 0
  try requireSuccess(
    LiteRtGetTensorBufferPackedSize(buffer, &size),
    operation: "Get output buffer size"
  )
  guard size.isMultiple(of: MemoryLayout<Float>.size) else {
    throw BenchmarkError.invalidFloat32BufferSize(size)
  }

  var address: UnsafeMutableRawPointer?
  try requireSuccess(
    LiteRtLockTensorBuffer(buffer, &address, kLiteRtTensorBufferLockModeRead),
    operation: "Lock output buffer"
  )
  let values = Array(
    UnsafeBufferPointer(
      start: try XCTUnwrap(address).assumingMemoryBound(to: Float.self),
      count: size / MemoryLayout<Float>.size
    )
  )
  try requireSuccess(LiteRtUnlockTensorBuffer(buffer), operation: "Unlock output buffer")
  return values
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

private func duration(since start: UInt64) -> Double {
  Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

private enum BenchmarkError: Error {
  case invalidFloat32BufferSize(Int)
  case requiresFloat32Tensors
}
