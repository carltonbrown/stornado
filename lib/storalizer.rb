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

class SwiftAccount
  def initialize(opts)
      os = opts['account']
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

  def get_container(name)
     return SwiftContainer.new(@os.container(name))
  end

  def create_repo(name)
     puts "Creating container #{name} in account #{@name}..."
     if @os.container_exists?(name)
       puts "Container #{name} already exists in account #{@name}, nothing to do."
     else
       return SwiftContainer.new(@os.create_container(name))
     end
  end

  def list_containers
     @os.containers
  end
end

class SwiftContainer
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
    config = JSON.parse(File.read(file))
    @repositories = config['repositories']
    @proxies = config['proxies']
    @accounts = config['object-stores']
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

  def get_container(rname)
      rconfig = @repositories.select do |repo|
        repo['name'] == rname
      end[0]
      os = get_account(rconfig['object-store'])
      return os.get_container(rconfig['name'])
  end

  def get_account(name)
      osconfig = @accounts.select do |account|
         account['name'] == name
      end[0]
      return SwiftAccount.new({'account' => osconfig, 'proxy' => @proxy})
  end
end

class RepoCommands
  def self.list(repo, arg)
    Proc.new { repo.send('list_detailed', arg) }
  end

  def self.ls(repo, arg)
    self.list(repo, arg)
  end

  def self.put(repo, opts)
    Proc.new { repo.send('put', opts) }
  end

  def self.get(repo, opts)
    Proc.new { repo.send('get', opts) }
  end
end

class AccountCommands
  def self.list(account, opts)
    Proc.new { account.send('list_containers') }
  end

  def self.ls(account, opts)
    self.list(account, opts)
  end

  def self.create(account, cname)
    Proc.new { account.send('create_repo', cname) }
  end
end

class MenuCommands
  def self.repo(config, args)
    rname = args.shift
    command = args.shift
    [ 'get', 'put' ].include?(command) && opts = {:src => args[0], :dst => args[1]}
    [ 'ls', 'list' ].include?(command) && opts = args[0]
    RepoCommands.send(command, config.get_container(rname), opts)
  end

  def self.account(config, args)
    (account_name, command, cname) = args
    [ 'create' ].include?(command) && opts = cname
    [ 'ls', 'list' ].include?(command) && opts = nil
    AccountCommands.send(command, config.get_account(account_name), opts)
  end
end

=begin
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: storalizer [options]"

  opts.on("-r FILE", "Repo config file") do |f|
    options[:repo_config] = f
  end

  opts.on("-p PROXY", "Proxy (as defined in config file)") do |proxy|
    options[:proxy_name] = proxy
  end
end.parse!

config = Configuration.new(options[:repo_config])
config.set_proxy(options[:proxy_name])

main_menu = ARGV.shift

puts MenuCommands.send(main_menu, config, ARGV).call
=end
