require 'digest/md5'
require 'json'
dumpfile = ARGV.pop
local_md5 = Digest::MD5.hexdigest(File.read(dumpfile))
data = {'path' => dumpfile, 'checksum' => local_md5, 'repo' => 'test-postgres-backups'}
puts JSON.pretty_generate(data)
