Gem::Specification.new do |s|
  s.name        = 'stornado'
  s.summary     = 'stornado - a swift client'
  s.authors     = 'Carlton Brown'
  s.version     = '0.0.5'
  s.executables << 'stornado'
  s.files       = ["lib/stornado.rb"]
  s.add_runtime_dependency 'openstack'
end
