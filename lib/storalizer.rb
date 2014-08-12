require 'json'
require 'optparse'
require 'openstack'

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
      if proxy.empty?
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
          :proxy_host => proxy['host'],
          :proxy_port => proxy['port'],
          :is_debug => false
        )
     end
  end

  def connection
    @os
  end

  def get_container(name)
     return SwiftContainer.new(name, self)
  end

  def create_container(opts)
     name = opts['container']
     config = opts['config']
     container = ''
     puts "Creating container #{name} in service #{@name}..."
     if @os.container_exists?(name)
       puts "Container #{name} already exists in service #{@name}, nothing to do."
     else
       if container = SwiftContainer.new(name, self)
         config.add_container(container)
       else
         raise "Failed to create container #{name}"
       end
     end
     return container
  end

  def delete_container(opts)
     name = opts['container']
     config = opts['config']
     retval = false
     puts "Deleting container #{name} in service #{@name}..."
     if @os.container_exists?(name)
       retval = @os.delete_container(name)
       puts "Container #{name} deleted."
     else
       puts "Container #{name} does not exist, nothing to do."
     end
     return retval
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

  def load_index
    @objects = {}
    @container.objects_detail.each do |fname, fmetadata|
      @objects[fname] = SwiftObject.new(fname, fmetadata)
    end
  end

  def metadata
    @container.container_metadata
  end

  def list(target)
    list_detailed(target)
  end

  def list_detailed(target)
    lines = []
    if target == nil
      @objects.each do |oname, object|
        lines.push(object.to_s)
      end
    else
      lines.push(@objects[target].to_s)
    end
    return lines.join("\n")
  end

  def read_file(fname)
    # There is a streaming reader if applicable but it seemed really slow for large files
    @container.object(fname).data
  end

  def delete(fname)
    puts "Deleting object #{fname}"
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

class Configuration
  def initialize(file)
    puts "Reading config file #{file}"
    config = JSON.parse(File.read(file))
    @file = file
    @containers = config['containers']
    @proxies = config['proxies']
    @services = config['services']
    @proxy = {}
  end

  def set_proxy(name)
      if name
        puts "Using proxy #{name}" if name
        @proxy = @proxies.select do |proxy|
          proxy['name'] == name
        end[0] || {}
      end
  end

  def get_container(cname)
      container_config = @containers.select do |container|
        container['name'] == cname
      end[0]
      svc = get_service(container_config['service'])
      return svc.get_container(container_config['name'])
  end

  def get_service(name)
      svcconfig = @services.select do |service|
         service['name'] == name
      end[0]
      return SwiftService.new({'service' => svcconfig, 'proxy' => @proxy})
  end

  def data
    return {
     'containers' => @containers,
     'proxies' => @proxies,
     'services' => @services
    }
  end

  def add_container(container)
     configfile = @file
     @containers.push({'name' => container.name, 'container' => container.name, 'service' => container.service.name })
     puts "Updating file #{configfile} with new container"
     File.open(configfile, 'w') {|f| f.write(JSON.pretty_generate(data)) }
     return true
  end
end

class RepoCommands
  def self.list(repo, arg)
    Proc.new { repo.send('list_detailed', arg) }
  end

  def self.ls(repo, arg)
    self.list(repo, arg)
  end

  def self.get(repo, opts)
    Proc.new { repo.send('get', opts) }
  end

  def self.put(repo, opts)
    Proc.new { repo.send('put', opts) }
  end

  def self.delete(repo, opts)
    Proc.new { repo.send('delete', opts[:target]) }
  end
end

class ServiceCommands
  def self.list(service, opts)
    Proc.new { service.send('list_containers') }
  end

  def self.ls(service, opts)
    self.list(service, opts)
  end

  def self.create(service, opts)
    Proc.new { service.send('create_container', opts) }
  end

  def self.delete(service, opts)
    Proc.new { service.send('delete_container', opts) }
  end
end

class MenuCommands
  def self.repo(config, args)
    rname = args.shift
    command = args.shift
    [ 'get', 'put', 'upload', 'download' ].include?(command) && opts = {:src => args[0], :dest => args[1]}
    [ 'delete', 'rm' ].include?(command) && opts = {:target => args[0]}
    [ 'ls', 'list' ].include?(command) && opts = args[0]
    RepoCommands.send(command, config.get_container(rname), opts)
  end

  def self.service(config, args)
    (service_name, command, cname) = args
    [ 'create', 'delete' ].include?(command) && opts = {'container' => cname, 'config' => config }
    [ 'ls', 'list' ].include?(command) && opts = nil
    ServiceCommands.send(command, config.get_service(service_name), opts)
  end
end
