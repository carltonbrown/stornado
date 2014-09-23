require 'digest/md5'
require 'fileutils'
require 'json'
require 'stornado'
require 'syslog'

class Request
  attr_accessor :props
  def initialize(file)
    @props = JSON.parse(IO.read(file))
    @props['parts'] ||= []
    @props['failures'] ||= 0
    @props['max_retries'] ||= 600
    set_source(file)
  end

  def failures
    @props['failures']
  end

  def max_retries
    @props['max_retries']
  end

  def parts
    @props['parts']
  end

  def set_parts_dir(dir)
    @props['parts_dir'] = dir
  end

  def set_source(file)
    @props['source'] = file
  end

  def source
    @props['source']
  end

  def save
    Syslog.log(Syslog::LOG_ERR, "saving message to #{source}")
    File.open(source, 'w+') { |file| file.write(to_s) }
  end

  def copy(path)
    Syslog.log(Syslog::LOG_ERR, "copying message from #{source} to #{path}")
    File.open(path, 'w+') { |file| file.write(to_s) }
  end

  def verify
    local_md5 = Digest::MD5.hexdigest(File.read(referent))
    if local_md5 != @props['checksum']
      Syslog.log(Syslog::LOG_ERR, "File has been changed since this backup was requested.  #{referent} was #{@props['checksum']}, Now #{local_md5}")
      raise "File has been changed since this backup was requested.  #{referent} was #{@props['checksum']}, Now #{local_md5}"
    else
      Syslog.log(Syslog::LOG_ERR, "verified checksum for #{referent}")
    end
  end

  def repo
    @props['repo']
  end

  def parts_dir
    @props['parts_dir']
  end

  def source
    @props['source']
  end

  def referent
    @props['path']
  end

  def to_s
    JSON.pretty_generate(@props)
  end
end

class DirQueue
  attr_accessor :dir
  include Enumerable
  def initialize(dir, pattern, name)
    @pattern = pattern
    @dir = dir
    @name = name
    if ! Dir.exist?(@dir)
       Dir.mkdir(@dir)
       Syslog.log(Syslog::LOG_ERR, "creating directory queue #{@dir}")
    end
  end

  def next
      if file = first
        Syslog.log(Syslog::LOG_ERR, "[#{name}] saw #{file}")
      end
      file
  end

  def name
    @name
  end

  def each
     files.each do |file|
       yield file if file.match(@pattern)
     end
  end

  def to_s
    @dir
  end

  def purge
    Dir.delete(@dir)
  end

  def enq(msg)
     newpath = @dir + "/" + File.basename(msg.source)
     msg.set_source(newpath)
     msg.save
     Syslog.log(Syslog::LOG_ERR, "[#{name}] queued #{msg.source}")
  end

  def deq(msg)
    deq_file(msg.source)
  end

  def deq_file(file)
    path = @dir + "/" + File.basename(file)
    Syslog.log(Syslog::LOG_ERR, "delete file #{path}")
    File.delete(path) if File.exist?(path)
  end

  def files
    Dir.entries(@dir).select {|entry|
        File.file?(@dir + '/' + entry)
      }.map {|entry|
        @dir + '/' + entry
      }
  end
end

class DirTransferHandler
  def initialize(opts, q)
    @opts = opts
    @partq = q
  end

  def handle(request)
    @repo = request.repo
    request.parts.each do |part|
      file = part['filename']
      begin
        transfer(file)
       @partq.deq_file(file) 
      rescue
        part['failures'] += 1
        Syslog.log(Syslog::LOG_ERR, "handler failed to process request - #{e.backtrace}.")
      end
      sleep 1
    end
  end

  def transfer(file)
    Syslog.log(Syslog::LOG_ERR, "copying #{file}...")
    FileUtils.cp(file, @repo)
  end
end

class StornadoUploadHandler < DirTransferHandler
  def initialize(opts, q)
     @partq = q
     @stornado = Stornado.new(opts)
  end

  def transfer(path)
    repo = @stornado.get_repo(@repo)
    dest = File.basename(path)
    Syslog.log(Syslog::LOG_ERR, "uploading #{path} to #{@repo}...")
    begin
      start_time = Time.now.to_i
      if repo.put({:src => path, :dest => dest})
        elapsed = Time.now.to_i - start_time
        Syslog.log(Syslog::LOG_ERR, "uploaded #{path} to #{@repo} in #{elapsed} seconds ...")
      else
        elapsed = start_time - Time.now.to_i
        raise "failed to upload #{path} to storage service after #{elapsed} seconds - #{e.message}." 
      end
    rescue
        raise "failed to upload #{path} to storage service after #{elapsed} seconds - #{e.message}." 
    end
  end
end

class SplitHandler
  attr_accessor :chunk_size
  def initialize(outq)
    @outq = outq
    # Swift limit is 5GB.  
    @chunk_size = 5 * 1024 * 1024 * 1024
  end

  def handle(request)
    request.verify
    path = request.referent
    basename = File.basename(path)
    destdir = @outq.dir
    Dir.chdir(destdir){
        Syslog.log(Syslog::LOG_ERR, "splitting #{path} into #{destdir} as #{@chunk_size} byte chunks")
        $stderr.puts %x[split -b #{@chunk_size} #{path} #{basename}.part_]
        @outq.each do |file|
          request.parts << {'filename' => file, 'md5sum' => Digest::MD5.hexdigest(File.read(file)), 'failures' => 0 }
        end
        manifest = "#{@outq.dir}/#{basename}.backup.json"
        request.parts << {'filename' => manifest, 'md5sum' => '' }
        request.save
        request.copy(manifest)
    }
  end
end

class QueueWorker
  attr_accessor :max_retries
  def initialize(inq, outq, handler)
    @in = inq
    @out = outq
    @handler = handler
  end

  def work
    while file = @in.next
      msg = Request.new(file)
      if msg.failures > msg.max_retries
        raise Syslog.log(Syslog::LOG_ERR, "Message exceeded retry limit of #{@max_retries} - #{e.backtrace}")
      end 
      begin
        @handler.handle(msg)
        @out.enq(msg)
        @in.deq(msg)
      rescue Exception => e
        msg.failures += 1
        Syslog.log(Syslog::LOG_ERR, "Worker method failed to process message - #{e.backtrace}")
      end
      sleep 1
    end
  end
end
