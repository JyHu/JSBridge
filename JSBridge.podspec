Pod::Spec.new do |s|
  s.name         = "JSBridge"
  s.version      = "0.0.1"
  s.summary      = "A framework for simplifying communication between JavaScript and native Swift."
  s.description  = <<-DESC
  JSBridge is a universal framework designed to simplify communication between JavaScript and client-side (OC, Swift). The framework provides powerful bidirectional communication mechanisms, supporting features like asynchronous calls, callback handling, and log management.
                   DESC
  s.homepage     = "https://github.com/JyHu/JSBridge"
  s.license      = "MIT"
  s.authors      = {
    "JyHu" => "auu.aug@gmail.com",
  }
  
  s.ios.deployment_target = '11.0'
  s.osx.deployment_target = '10.13'

  s.source       = { :git => "https://github.com/JyHu/JSBridge.git", :tag => s.version }
  s.requires_arc = true

  s.source_files = 'Sources/JSBridge/*.swift'
  s.resources = 'Sources/JSBridge/Resources/bridge.js'
end
