Gem::Specification.new do |s|
  s.name        = 'storhole'
  s.version     = '0.0.1'
  s.executables << 'storhole'
  s.files       = ["lib/storhole.rb"]
  s.add_runtime_dependency 'openstack'
end
