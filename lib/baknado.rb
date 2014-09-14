require 'digest/md5'
require 'fileutils'
require 'json'

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
      puts "Checksum verified."
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
       puts "apparently #{@dir} does not exist"
       Dir.mkdir(@dir)
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
     puts "Moving message #{msg.source} to #{@dir}"
     msg.write(newpath)
     File.delete(msg.source)
  end

  def deq(file)
    puts "Deleting #{file}"
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
      puts "Uploading #{part}"
      if transfer(part)
        partq.deq(part) 
      end
    end
    if ! partq.any? 
      partq.purge
    end
  end

  def transfer(file)
    puts "Transferring #{file}!"
    FileUtils.cp(file, @repo)
    return true
  end
end

class StornadoUploader < DirUploadHandler
  def initialize(opts)
     @stornado = Stornado.new(opts)
  end

  def transfer(path)
    repo = @stornado.get_repo(@repo)
    dest = File.basename(path)
    repo.put({:src => path, :dest => dest})
  end

end

class SplitHandler
  def initialize(dir)
    @workdir = dir
    # TODO change this for prod
    @chunk_size = 1 * 1024 * 1024
    FileUtils::mkdir_p(@workdir)
  end

  def handle(request)
    request.verify
    path = request.referent
    basename = File.basename(path)
    destdir = @workdir + '/' + basename + '.parts'
    puts "splitting #{path} into #{destdir}"
    FileUtils::mkdir_p(destdir)
    Dir.chdir(destdir){
        puts %x[split -b #{@chunk_size} #{path} #{basename}.part_]
        # TODO make this portable
        puts %x[openssl md5 * > #{basename}.md5] 
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
      @handler.handle(msg)
      @out.enq(msg)
    end
  end
end