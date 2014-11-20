require 'json'
require 'optparse'
require 'openstack'
require 'uri'

class SwiftObject
  attr_accessor :hash
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

  def hash(opts)
    target = opts[:target]
    @objects[target].hash
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
    puts "Reading #{opts[:src]}"
    payload=IO.binread(opts[:src])
    puts "Computing checksum"
    local_md5 = Digest::MD5.hexdigest(payload)
    puts "Uploading #{opts[:src]} as #{@name}/#{opts[:dest]}"
    puts "Computed local md5 digest #{local_md5}"
    new_obj = @container.create_object(opts[:dest], {}, payload)
    remote_md5 = new_obj.object_metadata[:etag]
    puts "Stored remotely with hash #{remote_md5}"
    if local_md5 != remote_md5
      raise "Transfer failed (remote hash #{remote_md5} differs from local hash #{local_md5})."
    end
    return new_obj
  end
end

class Stornado
  def initialize(opts)
    opts[:repo_config] ||= Dir.home + '/.stornado/repo-config.json'
    @file = opts[:repo_config]
    puts "Initializing with config #{opts[:repo_config]}" if opts[:debug]
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
      if repo_config == nil
         raise "No such configured repo - #{rname}"
      end
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

  def proxies
      @config['proxies'].map do |proxy|
         proxy['name'] + ":  " + proxy['host'] + ":" + proxy['port'] 
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
     'services' => @config['services'],
     'proxies' => @config['proxies']
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
     retval=false
     if dups.length > 0
        warn "Container #{container.name} already exists in #{container.service.name}"
     else
       puts "Updating file #{configfile} with new container #{container.name}"
       @config['containers'].push({'name' => container.name, 'container' => container.name, 'service' => container.service.name })
       File.open(configfile, 'w') {|f| f.write(JSON.pretty_generate(data)) }
       retval=true
     end
     return retval
  end
end

class RepoMenu
  def initialize(args, context)
    if args.length < 1
      puts "You must supply an argument"
      exit 1
    end
    @args = args
    @context = context
    rname = @args.shift
    @repo = @context.get_repo(rname)
  end

  def callback
    self.send(@args.shift)
  end

  def list
    Proc.new { @repo.list({:target => @args.shift}) }
  end

  def hash
    Proc.new { @repo.hash({:target => @args.shift}) }
  end

  alias :ls :list

  def download
    (target, dest) = @args.shift(2)
    Proc.new { 
      start_time = Time.now.to_f
      size = @repo.get({:src => target, :dest => dest}) 
      elapsed_time = Time.now.to_f - start_time 
      printf("Transferred %s bytes in %.3f seconds", size, elapsed_time)
    }
  end

  alias :get :download

  def upload
    (target, dest) = @args.shift(2)
    Proc.new { 
      start_time = Time.now.to_f
      result = @repo.put({:src => target, :dest => dest}) 
      elapsed_time = Time.now.to_f - start_time 
      printf("Transferred %s bytes in %.3f seconds", result.bytes, elapsed_time)
    }
  end

  alias :put :upload

  def delete
    target = @args.shift
    Proc.new { 
      result = @repo.delete({:target => target}) 
      "deleted=#{result}"
    }
  end

  alias :rm :delete
  alias :del :delete
end

class ServiceMenu
  def initialize(args, context)
    if args.length < 1
      puts "You must supply an argument"
      exit 1
    end
    @args = args
    @context = context
    svcname = @args.shift
    @service = @context.get_service(svcname)
  end

  def callback
    self.send(@args.shift)
  end

  def list
    Proc.new { @service.list_containers.join("\n") }
  end

  alias :ls :list

  def create
    name = @args.shift 
    # TODO it seems like the service should create the container, not the config
    Proc.new { @context.create_container(name, @service) }
  end

  def delete
    name = @args.shift 
    Proc.new { @service.delete_container(name) } 
  end
end

class MainMenu
  def initialize(args, context)
    if args.length < 1
      puts "You must supply an argument"
      exit 1
    end
    @args = args
    @context = context
  end

  def repo
    RepoMenu.new(@args, @context).callback
  end

  def service
    ServiceMenu.new(@args, @context).callback
  end

  def repos
    Proc.new { @context.send('repos').join("\n") }
  end

  def proxies
    Proc.new { @context.send('proxies').join("\n") }
  end

  def services
    Proc.new { @context.send('services').join("\n") }
  end

  def method_missing(m, *args, &block)  
    raise "Invalid argument - #{m}"
  end

  def callback
    self.send(@args.shift)
  end
end
