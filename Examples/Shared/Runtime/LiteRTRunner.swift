import CLiteRT
import Foundation

enum LiteRTRunner {
  static func runOnCPU() throws -> [Float] {
    try run(
      with: LiteRtHwAcceleratorSet(kLiteRtHwAcceleratorCpu.rawValue)
    )
  }

  static func runOnMetal() throws -> [Float] {
    try run(
      with: LiteRtHwAcceleratorSet(kLiteRtHwAcceleratorGpu.rawValue)
    )
  }

  private static func run(
    with hardwareAccelerators: LiteRtHwAcceleratorSet
  ) throws -> [Float] {
    guard let modelData = Data(
      base64Encoded: addModelBase64,
      options: .ignoreUnknownCharacters
    ) else {
      throw LiteRTExampleError.invalidModelData
    }

    var environment: LiteRtEnvironment?
    try validate(
      LiteRtCreateEnvironment(0, nil, &environment),
      operation: "Create environment"
    )
    guard let environment else {
      throw LiteRTExampleError.missingHandle("environment")
    }
    defer { LiteRtDestroyEnvironment(environment) }

    return try modelData.withUnsafeBytes { modelBytes in
      try run(
        modelBytes: modelBytes,
        environment: environment,
        hardwareAccelerators: hardwareAccelerators
      )
    }
  }

  private static func run(
    modelBytes: UnsafeRawBufferPointer,
    environment: LiteRtEnvironment,
    hardwareAccelerators: LiteRtHwAcceleratorSet
  ) throws -> [Float] {
    guard let modelAddress = modelBytes.baseAddress else {
      throw LiteRTExampleError.invalidModelData
    }

    var model: LiteRtModel?
    try validate(
      LiteRtCreateModelFromBuffer(
        environment,
        modelAddress,
        modelBytes.count,
        &model
      ),
      operation: "Create model"
    )
    guard let model else {
      throw LiteRTExampleError.missingHandle("model")
    }
    defer { LiteRtDestroyModel(model) }

    var options: LiteRtOptions?
    try validate(LiteRtCreateOptions(&options), operation: "Create options")
    guard let options else {
      throw LiteRTExampleError.missingHandle("options")
    }
    defer { LiteRtDestroyOptions(options) }
    try validate(
      LiteRtSetOptionsHardwareAccelerators(options, hardwareAccelerators),
      operation: "Select hardware accelerator"
    )

    var compiledModel: LiteRtCompiledModel?
    try validate(
      LiteRtCreateCompiledModel(environment, model, options, &compiledModel),
      operation: "Compile model"
    )
    guard let compiledModel else {
      throw LiteRTExampleError.missingHandle("compiled model")
    }
    defer { LiteRtDestroyCompiledModel(compiledModel) }

    return try run(
      environment: environment,
      model: model,
      compiledModel: compiledModel
    )
  }

  private static func run(
    environment: LiteRtEnvironment,
    model: LiteRtModel,
    compiledModel: LiteRtCompiledModel
  ) throws -> [Float] {
    var signature: LiteRtSignature?
    try validate(
      LiteRtGetModelSignature(model, 0, &signature),
      operation: "Get model signature"
    )
    guard let signature else {
      throw LiteRTExampleError.missingHandle("signature")
    }

    let inputType = try rankedTensorType(signature: signature, input: true)
    let outputType = try rankedTensorType(signature: signature, input: false)

    let inputBuffer = try createBuffer(
      environment: environment,
      compiledModel: compiledModel,
      tensorType: inputType,
      input: true
    )
    defer { LiteRtDestroyTensorBuffer(inputBuffer) }

    let outputBuffer = try createBuffer(
      environment: environment,
      compiledModel: compiledModel,
      tensorType: outputType,
      input: false
    )
    defer { LiteRtDestroyTensorBuffer(outputBuffer) }

    try write([1, 3], to: inputBuffer)

    var inputs: [LiteRtTensorBuffer?] = [inputBuffer]
    var outputs: [LiteRtTensorBuffer?] = [outputBuffer]
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
    try validate(status, operation: "Run model")

    return try read(count: 2, from: outputBuffer)
  }

  private static func createBuffer(
    environment: LiteRtEnvironment,
    compiledModel: LiteRtCompiledModel,
    tensorType: LiteRtRankedTensorType,
    input: Bool
  ) throws -> LiteRtTensorBuffer {
    var requirements: LiteRtTensorBufferRequirements?
    let requirementsStatus = input
      ? LiteRtGetCompiledModelInputBufferRequirements(compiledModel, 0, 0, &requirements)
      : LiteRtGetCompiledModelOutputBufferRequirements(compiledModel, 0, 0, &requirements)
    try validate(
      requirementsStatus,
      operation: input ? "Get input buffer requirements" : "Get output buffer requirements"
    )
    guard let requirements else {
      throw LiteRTExampleError.missingHandle(
        input ? "input buffer requirements" : "output buffer requirements"
      )
    }

    var mutableTensorType = tensorType
    var buffer: LiteRtTensorBuffer?
    try validate(
      LiteRtCreateManagedTensorBufferFromRequirements(
        environment,
        &mutableTensorType,
        requirements,
        &buffer
      ),
      operation: input ? "Create input buffer" : "Create output buffer"
    )
    guard let buffer else {
      throw LiteRTExampleError.missingHandle(input ? "input buffer" : "output buffer")
    }
    return buffer
  }

  private static func rankedTensorType(
    signature: LiteRtSignature,
    input: Bool
  ) throws -> LiteRtRankedTensorType {
    var tensor: LiteRtTensor?
    let status = input
      ? LiteRtGetSignatureInputTensorByIndex(signature, 0, &tensor)
      : LiteRtGetSignatureOutputTensorByIndex(signature, 0, &tensor)
    try validate(status, operation: input ? "Get input tensor" : "Get output tensor")

    guard let tensor else {
      throw LiteRTExampleError.missingHandle(input ? "input tensor" : "output tensor")
    }

    var tensorType = LiteRtRankedTensorType()
    try validate(
      LiteRtGetRankedTensorType(tensor, &tensorType),
      operation: input ? "Get input tensor type" : "Get output tensor type"
    )
    return tensorType
  }

  private static func write(
    _ values: [Float],
    to buffer: LiteRtTensorBuffer
  ) throws {
    var address: UnsafeMutableRawPointer?
    try validate(
      LiteRtLockTensorBuffer(buffer, &address, kLiteRtTensorBufferLockModeWrite),
      operation: "Lock input buffer"
    )
    guard let address else {
      throw LiteRTExampleError.missingHandle("input buffer memory")
    }

    values.withUnsafeBufferPointer { values in
      guard let baseAddress = values.baseAddress else {
        return
      }
      address.copyMemory(
        from: baseAddress,
        byteCount: values.count * MemoryLayout<Float>.size
      )
    }

    try validate(LiteRtUnlockTensorBuffer(buffer), operation: "Unlock input buffer")
  }

  private static func read(
    count: Int,
    from buffer: LiteRtTensorBuffer
  ) throws -> [Float] {
    var address: UnsafeMutableRawPointer?
    try validate(
      LiteRtLockTensorBuffer(buffer, &address, kLiteRtTensorBufferLockModeRead),
      operation: "Lock output buffer"
    )
    guard let address else {
      throw LiteRTExampleError.missingHandle("output buffer memory")
    }

    let values = Array(
      UnsafeBufferPointer(
        start: address.assumingMemoryBound(to: Float.self),
        count: count
      )
    )
    try validate(LiteRtUnlockTensorBuffer(buffer), operation: "Unlock output buffer")
    return values
  }

  private static func validate(
    _ status: LiteRtStatus,
    operation: String
  ) throws {
    guard status == kLiteRtStatusOk else {
      let message = LiteRtGetStatusString(status).map(String.init(cString:)) ?? "unknown status"
      throw LiteRTExampleError.operationFailed(operation, message)
    }
  }

  // TensorFlow Lite add.bin: float32[2] -> multiply by 3 -> float32[2].
  // Source: tensorflow/tensorflow v2.17.0, tensorflow/lite/testdata/add.bin.
  private static let addModelBase64 = """
  JAAAAFRGTDMAAAAAAAAAABQAGAAEAAgADAAAABAAAAAAABQAFAAAAAMAAADkAQAAmAAAAIAAAAAE
  AAAAAQAAABAAAAAAAAoAEAAEAAgADAAKAAAAPAAAABwAAAAEAAAADwAAAHNlcnZpbmdfZGVmYXVs
  dAABAAAABAAAAOT///8IAAAAAgAAAAEAAAB4AAAAAQAAAAwAAAAIAAwABAAIAAgAAAAIAAAAAQAA
  AAEAAABhAAAAAQAAAAQAAACk/v//AAAAAAAAAAABAAAAEAAAAAwAFAAEAAgADAAQAAwAAACUAAAA
  iAAAAHwAAAAEAAAAAgAAAEQAAAAEAAAA0v///wAAAAsYAAAADAAAAAQAAAD4/v//AQAAAAIAAAAC
  AAAAAAAAAAEAAAAAAA4AFAAAAAgADAAHABAADgAAAAAAAAsYAAAADAAAAAQAAAA0////AQAAAAAA
  AAACAAAAAQAAAAEAAAABAAAAAgAAAAEAAAABAAAAAwAAAHAAAAA0AAAABAAAAKj///8UAAAABAAA
  AAYAAABvdXRwdXQAAAQAAAABAAAACAAAAAgAAAADAAAA1P///xQAAAAEAAAABQAAAGlucHV0AAAA
  BAAAAAEAAAAIAAAACAAAAAMAAAAMAAwABAAAAAAACAAMAAAAEAAAAAQAAAADAAAAYWRkAAQAAAAB
  AAAACAAAAAgAAAADAAAAAQAAAAgAAAAEAAQABAAAAA==
  """
}

private enum LiteRTExampleError: Error, CustomStringConvertible {
  case invalidModelData
  case missingHandle(String)
  case operationFailed(String, String)

  var description: String {
    switch self {
    case .invalidModelData:
      return "Invalid embedded model data"
    case let .missingHandle(name):
      return "LiteRT returned no \(name)"
    case let .operationFailed(operation, message):
      return "\(operation) failed: \(message)"
    }
  }
}
