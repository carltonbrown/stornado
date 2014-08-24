require 'json'
require 'optparse'
require 'openstack'
require 'uri'

class SwiftObject
  def initialize(name, md)
       # fields:  bytes, content_type, last_modified, hash
       @name = name
       @bytes = md[:bytes]
       @content_type = md[:content_type]
       @last_modified = md[:last_modified]
       @hash = md[:hash]
  end

  def to_s
       sprintf("%32s  %34s  %10d  %26s  %s", @hash, @content_type, @bytes, @last_modified, @name)
  end
end

class SwiftService
  attr_accessor :type, :name
  def initialize(opts)
      os = opts['service']
      @name = os['name']
      @type = os['service_type']
      proxy = opts['proxy']
      connection_user = "#{os['storage_id']}-#{os['identity_domain']}:#{os['user']}"
      if proxy == nil
        @os = OpenStack::Connection.create(
          :username => connection_user,
          :api_key => os['auth_key'],   # either password or api key.   This is not the auth token
          :auth_url => os['auth_url'], 
          :service_type => @type,
          :auth_method => os['auth_method'],
          :is_debug => false
        )
     else
        @os = OpenStack::Connection.create(
          :username => connection_user,
          :api_key => os['auth_key'],   # either password or api key.   This is not the auth token
          :auth_url => os['auth_url'], 
          :service_type => @type,
          :auth_method => os['auth_method'],
          :proxy_host => proxy.host,
          :proxy_port => proxy.port,
          :is_debug => false
        )
     end
  end

  def to_s
    sprintf("%s", @name)
  end

  def connection
    @os
  end

  def get_container(name)
     return SwiftContainer.new(name, self)
  end

  def create_container(name)
     container = SwiftContainer.new(name, self)
  end

  def delete_container(name)
     retval = false
     puts "Deleting container #{name} from service #{@name}..."
     if @os.container_exists?(name)
       retval = @os.delete_container(name)
       puts "Container #{name} deleted."
     else
       puts "Container #{name} does not exist, nothing to do."
     end
     return retval
  end

  def containers
     @os.containers
  end

  def list_containers
     @os.containers
  end
end

class SwiftContainer
  attr_accessor :name, :service, :container
  def initialize(name, service)
     @container = service.connection.create_container(name)
     @name = name
     @service = service
     load_index
  end

  def to_s
    self.service.to_s + ':' + self.name.to_s
  end

  def load_index
    @objects = {}
    @container.objects_detail.each do |fname, fmetadata|
      @objects[fname] = SwiftObject.new(fname, fmetadata)
    end
  end

  def metadata
    @container.container_metadata
  end

  def list(opts)
    list_detailed(opts)
  end

  def files
    lines = []
    @objects.each do |oname, object|
      lines.push(object.to_s)
    end
    return lines
  end

  def list_detailed(opts)
    target = opts[:target]
    lines = []
    if target == nil
      lines = files
    else
      lines.push(@objects[target].to_s)
    end
    return lines.join("\n")
  end

  def files
    @objects.map do |oname, object|
     object.to_s
    end
  end

  def read_file(fname)
    # There is a streaming reader if applicable but it seemed really slow for large files
    @container.object(fname).data
  end

  def delete(opts)
    fname = opts[:target]
    puts "Delete object #{fname}"
    @container.delete_object(fname)
  end

  def get(opts)
    raise "No source file specified" unless opts[:src]
    opts[:dest] ||= opts[:src]
    puts "Retrieving #{opts[:src]} from #{@name} to #{opts[:dest]}"
    File.open(opts[:dest], 'w') {|f| f.write(read_file(opts[:src])) }
  end

  def put(opts)
    raise "No source file specified" unless opts[:src]
    opts[:dest] ||= opts[:src]
    puts "Uploading #{opts[:src]} to #{@name} as #{opts[:dest]}"
    new_obj = @container.create_object(opts[:dest], {:metadata=>{"myname"=>"myval"}}, IO.read(opts[:src]))
  end
end

class Stornado
  def initialize(opts)
    opts[:repo_config] ||= Dir.home + '/.stornado/repo-config.json'
    @file = opts[:repo_config]
    puts "Initializing with config #{opts[:repo_config]}"
    @config = JSON.parse(File.read(opts[:repo_config]))
    if opts[:proxy]
       # unpack it from the config
      proxies = []
      if @config['proxies']
        proxies = @config['proxies'].select do |proxy|
          proxy['name'] == opts[:proxy]
        end
      end
      if proxies.length < 1
        raise "There's no configured proxy named #{opts[:proxy]}"
      end
      proxy = proxies.shift
      @proxy = URI::HTTP.build(
        {:host => proxy['host'], :port => proxy['port'].to_i}
      )
    else
      (ENV['HTTP_PROXY']) == nil ? @proxy = nil : @proxy = URI(ENV['HTTP_PROXY'])
    end

    if @proxy
      puts "Using proxy #{@proxy}"
    end
  end

  def get_repo(rname)
      repo_config = @config['containers'].select do |repo|
        repo['name'] == rname
      end[0]
      svc = get_service(repo_config['service'])
      return svc.get_container(repo_config['container'])
  end

  def get_service(name)
      svcconfig = @config['services'].select do |service|
         service['name'] == name
      end[0]
      return SwiftService.new({'service' => svcconfig, 'proxy' => @proxy})
  end

  def services
      @config['services'].map do |service|
         service['name'] + ":  " + service['user'] 
      end
  end

  def repos
      @config['containers'].map do |repo|
         repo['service'] + "/" + repo['container'] 
      end
  end

  def data
    return {
     'containers' => @config['containers'],
     'services' => @config['services']
    }
  end

  def create_container(name, service)
      container = service.create_container(name)
      raise "Container not created" unless container
      self.add_container(container)
  end

  def add_container(container)
     configfile = @file
     dups = @config['containers'].select do |repo|
        repo['name'] == container.name && repo['service'] == container.service.name
     end
     if dups.length > 0
        warn "Container #{container.name} already exists in #{container.service.name}"
     end
     puts "Updating file #{configfile} with new container #{container.name}"
     @config['containers'].push({'name' => container.name, 'container' => container.name, 'service' => container.service.name })
     File.open(configfile, 'w') {|f| f.write(JSON.pretty_generate(data)) }
     return true
  end
end

class RepoCommands
  def self.list(opts)
    p = Proc.new { opts[:repo].send('list_detailed', opts) }
    # A bit janky. 
    puts p.call
    return p
  end

  def self.ls(opts)
    self.list(opts)
  end

  def self.get(opts)
    Proc.new { opts[:repo].send('get', opts) }
  end

  def self.put(opts)
    Proc.new { opts[:repo].send('put', opts) }
  end

  def self.delete(opts)
    Proc.new { opts[:repo].send('delete', opts) }
  end
end

class ServiceCommands
  def self.list(opts)
    p = Proc.new { opts[:service].send('list_containers').join("\n") }
    puts p.call
    return p
  end

  def self.ls(opts)
    self.list(opts)
  end

  def self.create(opts)
    raise "Container not specified" unless opts[:container]
    Proc.new { opts[:config].send('create_container', opts[:container], opts[:service]) }
  end

  def self.delete(opts)
    raise "Container not specified" unless opts[:container]
    Proc.new { opts[:service].send('delete_container', opts[:container]) }
  end
end

class ConfigCommands
  def self.services(opts)
    p = Proc.new { 
      opts[:config].send('services').join("\n")
    }
    # A bit janky. 
    puts p.call
    return p
  end

  def self.repos(opts)
    p = Proc.new { 
      opts[:config].send('repos').join("\n")
    }
    # A bit janky. 
    puts p.call
    return p
  end
end

class MenuCommands
  def self.repo(config, args)
    rname = args.shift
    repo = config.get_repo(rname)
    command = args.shift
    [ 'get', 'put', 'upload', 'download' ].include?(command) && opts = {:repo => repo, :src => args[0], :dest => args[1]}
    [ 'delete', 'rm' ].include?(command) && opts = {:repo => repo, :target => args[0]}
    [ 'ls', 'list' ].include?(command) && opts = {:repo => repo, :target => args[0]}
    RepoCommands.send(command, opts)
  end

  def self.service(config, args)
    (service_name, command, cname) = args
    service = config.get_service(service_name)
    [ 'create', 'delete' ].include?(command) && opts = {:service => service, :container => cname, :config => config }
    [ 'ls', 'list' ].include?(command) && opts = {:service => service}
    ServiceCommands.send(command, opts)
  end

  def self.services(config, args)
    opts = {:config => config }
    ConfigCommands.send('services', opts)
  end

  def self.repos(config, args)
    opts = {:config => config }
    ConfigCommands.send('repos', opts)
  end
end
