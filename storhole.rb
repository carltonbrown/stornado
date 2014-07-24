require 'openstack'
require 'json'

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
       "#{@hash}\t#{@content_type}\t#{@bytes}\t#{@last_modified}\t#{@name}"
       #443f65adbb5ef7f53a9d1623d5fa5796	application/x-tar	276313160	2014-07-08T19:18:04.267290	accounts-fd5b46498bdc085772da398ee3d7fab6839d4300.tgz
       #c6ac3880e5a247282e6d515ad2f65efd	application/x-www-form-urlencoded	29	2014-07-23T14:15:03.126640	foo
       sprintf("%32s  %34s  %10d  %26s  %s", @hash, @content_type, @bytes, @last_modified, @name)
  end
end

class SwiftObjectStore
  def initialize(opts)
      os = opts['os']
      @name = os['name']
      proxy = opts['proxy']
      if proxy
        @os = OpenStack::Connection.create(
          :proxy_host => proxy['host'],
          :proxy_port => proxy['port'],
          :username => "#{os['storage_id']}-#{os['identity_domain']}:#{os['user']}",
          :api_key => os['auth_key'],   # either password or api key.   This is not the auth token
          :auth_url => os['auth_url'], 
          :service_type => "object-store",
          :auth_method => os['auth_method'],
          :is_debug => false
        )
     else
        @os = OpenStack::Connection.create(
          :username => "#{os['storage_id']}-#{os['identity_domain']}:#{os['user']}",
          :api_key => os['auth_key'],   # either password or api key.   This is not the auth token
          :auth_url => os['auth_url'], 
          :service_type => "object-store",
          :auth_method => repo['auth_method'],
          :is_debug => false
        )
     end
  end

  def get_repo(name)
     return SwiftRepo.new(@os.container(name))
  end

  def create_repo(name)
     puts "Creating container #{name} in store #{@name}..."
     if @os.container_exists?(name)
       puts "Container #{name} already exists in store #{@name}, nothing to do."
     else
       return SwiftRepo.new(@os.create_container(name))
     end
  end

  def list_containers
     @os.containers
  end
end

class SwiftRepo
  def initialize(container)
     @container = container
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
    retval = nil
    if target == nil
      retval = @container.objects
    else
      retval = list_detailed(target)
    end
    return retval
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

  def get(opts)
    raise "No source file specified" unless opts[:src]
    opts[:dest] ||= opts[:src]
    puts "Retrieving #{opts[:src]} from "#{@name}" to #{opts[:dest]}"
    File.open(opts[:dest], 'w') {|f| f.write(read_file(opts[:src])) }
  end

  def put(opts)
    raise "No source file specified" unless opts[:src]
    opts[:dest] ||= opts[:src]
    puts "Uploading #{opts[:src]} to #{@name} as #{opts[:dest]}"
    new_obj = @container.create_object(opts[:dest], {:metadata=>{"myname"=>"myval"}}, IO.read(opts[:src]))
  end
end

class RepoConfig
  def initialize(file)
    config = JSON.parse(File.read(file))
    @repositories = config['repositories']
    @proxies = config['proxies']
    @ostores = config['object-stores']
  end

  def set_proxy(name)
      puts "Using proxy #{name}" if name
      if name
        @proxy = @proxies.select do |name|
          proxy['name'] == name
        end[0] || {}
      else 
        @proxy = {}
      end
  end

  def get(rname)
      rconfig = @repositories.select do |repo|
        repo['name'] == rname
      end[0]
      osconfig = @ostores.select do |ostore|
         ostore['name'] == rconfig['object-store']
      end[0]

      os = SwiftObjectStore.new({'os' => osconfig, 'proxy' => @proxy})
      return os.get_repo(rconfig['name'])
  end

  def create(sname, cname)
      osconfig = @ostores.select do |ostore|
         ostore['name'] == sname
      end[0]
      os = SwiftObjectStore.new({'os' => osconfig, 'proxy' => @proxy})
      repo = os.create_repo(cname)
  end

  def ls(sname)
      osconfig = @ostores.select do |ostore|
         ostore['name'] == sname
      end[0]
      os = SwiftObjectStore.new({'os' => osconfig, 'proxy' => @proxy})
      os.list_containers
  end
end

require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"

  opts.on("-r FILE", "Repo config") do |f|
    options[:repo_config] = f
  end

  opts.on("-p PROXY", "Proxy (as defined in config file)") do |proxy|
    options[:proxy_name] = proxy
  end
end.parse!

puts "Load config from #{options[:repo_config]}"
config = RepoConfig.new(options[:repo_config])
config.set_proxy(options[:proxy_name])

fname = 'accounts-dfcee01869debc8367c104e46219ee612856b299.tgz' # A 200+ MB tarfile
#fname = 'accounts-22311d8f0ef6d359190ced9ee3ab130bc2236f7d.tgz' # An 800 KB tarfile

# Example:  ruby storhole.rb repo get production-releases accounts-22311d8f0ef6d359190ced9ee3ab130bc2236f7d.tgz -r repo_config.json -p ch3-opc
# Example:  ruby storhole.rb repo ls production-releases accounts-22311d8f0ef6d359190ced9ee3ab130bc2236f7d.tgz -r repo_config.json -p ch3-opc
# Example:  ruby storhole.rb repo ls_l production-releases accounts-22311d8f0ef6d359190ced9ee3ab130bc2236f7d.tgz -r repo_config.json -p ch3-opc

main_commands = ['repo', 'store']
main_cmd = ARGV.shift
raise "Command #{main_cmd} not recognized" if ! main_commands.include?(main_cmd)

if main_cmd == 'repo'
  subcommand = ARGV.shift
  rname = ARGV.shift
  puts "Configuring repository #{rname}"
  output = ''
  repo = config.get(rname, options[:proxy_name])
  subcommand == 'get' && repo.send('get', {:src => ARGV[0], :dst => ARGV[1]})
  subcommand == 'put' && repo.send('put', {:src => ARGV[0], :dst => ARGV[1]})
  subcommand == 'ls' && output = repo.send('list', ARGV[0])
  subcommand == 'ls_l' && output = repo.send('list_detailed', ARGV[0])
  puts output
elsif main_cmd == 'store'
  subcommand = ARGV.shift
  sname = ARGV.shift
  cname = ARGV.shift
  output = ''
  subcommand == 'create' && config.create(sname, cname)
  subcommand == 'list' && output = config.ls(sname)
  puts output
end
