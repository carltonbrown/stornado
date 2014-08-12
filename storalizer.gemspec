Gem::Specification.new do |s|
  s.name        = 'storalizer'
  s.summary     = 'storalizer - a swift client'
  s.authors     = 'Carlton Brown'
  s.version     = '0.0.2'
  s.executables << 'storalizer'
  s.files       = ["lib/storalizer.rb"]
  s.add_runtime_dependency 'openstack'
end
