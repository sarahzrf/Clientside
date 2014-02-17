Gem::Specification.new do |s|
  s.name        = 'clientside'
  s.version     = '0.4.4'
  s.date        = Date.today.to_s
  s.summary     = 'Use server Ruby objects from client JS!'
  s.description = 'A simple Rack middleware and JavaScript generator for ' +
                  'basic remote method invocation over websockets.'
  s.authors     = ['benzrf']
  s.email       = 'benzrf@benzrf.com'
  s.files       = Dir['lib/**/*'] + Dir['examples/**/*']
  s.homepage    = 'http://rubygems.org/gems/clientside'
  s.license     = 'LGPL'

  s.add_runtime_dependency 'faye-websocket'
  s.add_runtime_dependency 'rack'
end

