import Darwin

enum LiteRTMetalRegistration {
  static func withRegisteredAccelerator<T>(
    _ operation: (UnsafeMutableRawPointer) throws -> T
  ) throws -> T {
    guard let process = dlopen(nil, RTLD_NOW) else {
      throw LiteRTMetalRegistrationError.processUnavailable
    }
    let acceleratorDefinition = try symbol("LiteRtAcceleratorImpl", in: process)
    let registration = try symbol(
      "LiteRtStaticLinkedAcceleratorGpuDef",
      in: process
    ).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
    let previousDefinition = registration.pointee
    registration.pointee = acceleratorDefinition
    defer { registration.pointee = previousDefinition }

    return try operation(process)
  }

  private static func symbol(
    _ name: String,
    in process: UnsafeMutableRawPointer
  ) throws -> UnsafeMutableRawPointer {
    guard let address = dlsym(process, name) else {
      throw LiteRTMetalRegistrationError.symbolUnavailable(name)
    }
    return address
  }
}

private enum LiteRTMetalRegistrationError: Error {
  case processUnavailable
  case symbolUnavailable(String)
}
