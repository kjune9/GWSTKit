Pod::Spec.new do |s|
  s.name             = 'subject_sticker'
  s.version          = '0.1.0'
  s.summary          = 'On-device subject cutout for sticker-style photo editing.'
  s.description      = <<-DESC
On-device subject cutout using the Vision foreground instance mask
(iOS 17+ at runtime; gracefully unsupported below).
                       DESC
  s.homepage         = 'https://github.com/kjune9/GWSTKit'
  s.license          = { :type => 'MIT' }
  s.author           = { 'GWST' => 'kjune9oo@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'subject_sticker/Sources/subject_sticker/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
