require 'digest/md5'
require 'fileutils'
require 'json'
require 'stornado'

class Request
  def initialize(file)
    @props = JSON.parse(IO.read(file))
  end

  def set_parts(parts)
    @props['parts'] = parts
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
    if local_md5 != checksum
      raise "File has been changed since this backup was requested."
    else
      puts "Checksum OK."
    end
  end

  def parts
    @props['parts']
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

  def checksum
    @props['checksum']
  end

  def workdir
    @props['workdir']
  end

  def container
    @props['container']
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
    puts "Dleteing #{file}"
    File.delete(file) if File.exist?(file)
  end

  def files
    puts "Scanning #{@dir}"
    Dir.entries(@dir).select {|entry|
        File.file?(@dir + '/' + entry)
      }.map {|entry|
        @dir + '/' + entry
      }
  end
end

class UploadHandler
  def initialize(dir)
    @remote_dir = dir
  end

  def handle(request)
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
    FileUtils.cp(file, @remote_dir)
    return true
  end
end

class StornadoHandler < UploadHandler
  def initialize(repo)
    @repo = repo 
  end

  def transfer(path)
    dest = File.basename(path)
    puts "DEBUG: transfer #{path} to #{dest}"
    @repo.put({:src => path, :dest => dest})
  end

end

class SplitHandler
  def initialize(dir)
    @workdir = dir
    # TODO change this for prod
    @chunk_size = 5 * 1024 * 1024
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
        puts %x[openssl md5 * > #{basename}.md5] 
    }
=begin
    parts = Dir.entries(destdir).select {|entry|
      File.file?(destdir + '/' + entry)
    }.map {|entry|
      destdir + '/' + entry
    }
=end
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
      puts msg.to_s
      sleep 1
    end
  end
end

#upload_handler = UploadHandler.new('/tmp/backup/remote')
cname = 'test-postgres-backups'
stornado = Stornado.new({})
repo = stornado.get_repo(cname)

upload_handler = StornadoHandler.new(repo)

split_handler = SplitHandler.new('/tmp/backup/split')
ready = DirQueue.new('/tmp/backup/ready', Regexp.new('\.msg.json'))
processing = DirQueue.new('/tmp/backup/processing', Regexp.new('\.msg.json'))
complete = DirQueue.new('/tmp/backup/complete', Regexp.new('\.msg.json'))
prepper = QueueWorker.new(ready, processing, split_handler)
prepper.work

shipper = QueueWorker.new(processing, complete, upload_handler)
shipper.work
