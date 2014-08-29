major = ENV['GEM_MAJOR'] || '0'
minor = ENV['GEM_MINOR'] || '1'
patch = ENV['GEM_PATCH'] || '0'

version = sprintf("%s.%s.%s", major, minor, patch)

Gem::Specification.new do |s|
  s.name        = 'stornado'
  s.summary     = 'stornado - a swift client'
  s.authors     = 'Carlton Brown'
  s.version     = version
  s.executables << 'stornado'
  s.files       = ["lib/stornado.rb"]
  s.add_runtime_dependency 'openstack'
end
