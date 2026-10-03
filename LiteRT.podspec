Pod::Spec.new do |spec|
  spec.name = 'LiteRT'
  spec.version = '2.1.6'
  spec.authors = 'Google Inc.'
  spec.license = { :type => 'Apache-2.0', :file => 'LICENSE' }
  spec.homepage = 'https://github.com/google-ai-edge/LiteRT'
  spec.source = {
    :http => "https://github.com/pinge/litert-ios/releases/download/v#{spec.version}/LiteRT.xcframeworks.zip",
    :sha256 => '1c76257477cca5a31c372903bec448691196db6043b0c4da272aa05da1493730'
  }
  spec.summary = 'LiteRT runtime and Metal accelerator for iOS.'
  spec.cocoapods_version = '>= 1.9.0'
  spec.ios.deployment_target = '15.0'
  spec.vendored_frameworks = [
    'CLiteRT.xcframework',
    'LiteRTMetalAccelerator.xcframework'
  ]
end
