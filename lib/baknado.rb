require 'digest/md5'
require 'fileutils'
require 'json'
require 'stornado'
require 'syslog'

class Request
  attr_accessor :props
  def initialize(file)
    @props = JSON.parse(IO.read(file))
  end

  def set_parts_dir(dir)
    @props['parts_dir'] = dir
  end

  def set_source(file)
    @props['source'] = file
  end

  def write(path)
    File.open(path, 'w') { |file| file.write(to_s) }
  end

  def verify
    local_md5 = Digest::MD5.hexdigest(File.read(referent))
    if local_md5 != @props['checksum']
      raise "File has been changed since this backup was requested.  #{referent} was #{@props['checksum']}, Now #{local_md5}"
    else
      Syslog.log(Syslog::LOG_INFO, "Verified checksum for #{referent}")
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
  include Enumerable
  def initialize(dir, pattern)
    @pattern = pattern
    @dir = dir
    if ! Dir.exist?(@dir)
       Dir.mkdir(@dir)
       Syslog.log(Syslog::LOG_INFO, "Creating directory queue #{@dir}")
    end
  end

  alias :next :first

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
     Syslog.log(Syslog::LOG_INFO, "Moving message #{msg.source} to #{@dir}")
     msg.write(newpath)
     File.delete(msg.source)
  end

  def deq(file)
    Syslog.log(Syslog::LOG_DEBUG, "Deleting message #{file}")
    File.delete(file) if File.exist?(file)
  end

  def files
    Dir.entries(@dir).select {|entry|
        File.file?(@dir + '/' + entry)
      }.map {|entry|
        @dir + '/' + entry
      }
  end
end

class DirUploadHandler
  def handle(request)
    @repo = request.repo
    partq = DirQueue.new(request.parts_dir, /./)
    while part = partq.next
      begin
        transfer(part)
        partq.deq(part) 
      rescue
        Syslog.log(Syslog::LOG_ERR, "Transfer of #{part} failed.")
      end
    end
    if ! partq.any? 
      partq.purge
    end
  end

  def transfer(file)
    Syslog.log(Syslog::LOG_INFO, "Copying #{file}...")
    FileUtils.cp(file, @repo)
  end
end

class StornadoUploader < DirUploadHandler
  def initialize(opts)
     @stornado = Stornado.new(opts)
  end

  def transfer(path)
    repo = @stornado.get_repo(@repo)
    dest = File.basename(path)
    Syslog.log(Syslog::LOG_INFO, "uploading #{path} to #{@repo}...")
    repo.put({:src => path, :dest => dest})
  end

end

class SplitHandler
  attr_accessor :chunk_size
  def initialize(dir)
    @workdir = dir
    # Swift limit is 5GB.  
    @chunk_size = 5 * 1024 * 1024 * 1024
    FileUtils::mkdir_p(@workdir)
  end

  def handle(request)
    request.verify
    path = request.referent
    basename = File.basename(path)
    destdir = @workdir + '/' + basename + '.parts'
    FileUtils::mkdir_p(destdir)
    Dir.chdir(destdir){
        Syslog.log(Syslog::LOG_INFO, "splitting #{path} into #{destdir} as #{@chunk_size} byte chunks")
        $stderr.puts %x[split -b #{@chunk_size} #{path} #{basename}.part_]
        # TODO make this portable
        Syslog.log(Syslog::LOG_INFO, "writing checksums to #{basename}.md5")
        $stderr.puts %x[md5sum * > #{basename}.md5] 
    }
    request.set_parts_dir(destdir)
  end
end

class QueueWorker
  def initialize(inq, outq, handler)
    @in = inq
    @out = outq
    @handler = handler
  end

  def work
    while file = @in.next
      msg = Request.new(file)
      msg.set_source(file)
      begin
        @handler.handle(msg)
        @out.enq(msg)
      rescue Exception => e
        Syslog.log(Syslog::LOG_ERR, "Failed to process request #{msg} - #{e.message}")
      end
    end
  end
end
