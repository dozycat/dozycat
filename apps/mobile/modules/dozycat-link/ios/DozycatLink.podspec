Pod::Spec.new do |s|
  s.name = 'DozycatLink'
  s.version = '0.1.0'
  s.summary = 'Native accountless dozycat pairing'
  s.description = 'Noise device authorization and LAN connections'
  s.author = 'dozycat'
  s.homepage = 'https://dozycat.ai'
  s.license = 'MIT'
  s.platforms = { :ios => '16.4' }
  s.source = { :git => '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.source_files = '**/*.swift'
  s.vendored_frameworks = 'dozycat_linkFFI.xcframework'
  s.frameworks = 'Network', 'Security'
  s.swift_version = '5.9'
end
