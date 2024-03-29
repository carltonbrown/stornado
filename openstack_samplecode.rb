# Get info on container count and bytes:
# os.get_info
# => {:count=>2, :bytes=>495041}
#
# # Get list of containers under this account:
# os.containers
# => ["another_containerfoo", "marios_test_container"]
#
# # Get details of containers under this account:
# >> os.containers_detail
# =>=> {"another_containerfoo"=>{:count=>"3", :bytes=>"1994"}, "marios_test_container"=>{:count=>"2", :bytes=>"493047"}}
#
# # Check if a container exists
# >> os.container_exists?("no_such_thing")
# => false
#
# # Create new container
# >> os.create_container("foo")
# => => #<OpenStack::Swift::Container:0xb7275c38  ...... (rest of OpenStack::Swift::Container object)
#
# # Delete container
# >> os.delete_container("foo")
# => true
#
# # Get a container (OpenStack::Swift::Container object):
# >> cont = os.container("foo")
# => #<OpenStack::Swift::Container:0xb7262124 ...... (rest of OpenStack::Swift::Container object)
#
# # Retrieve container metadata:
# >> cont.container_metadata
# =>{:count=>"2", :bytes=>"493047", :metadata=>{"foo"=>"bar", "author"=>"foobar", "jj"=>"foobar", "date"=>"today", "owner"=>"foo"}}
#
# # Retrieve user defined metadata:
# >> cont.metadata
# => {"foo"=>"bar", "author"=>"foobar", "jj"=>"foobar", "date"=>"today", "owner"=>"foo"}
#
# # Set user defined metadata:
# >> cont.set_metadata({"X-Container-Meta-Author"=> "msa", "version"=>"1.2", :date=>"today"})
# => true
#
# # Get list of objects:
# >> cont.objects
# => ["fosdem2012.pdf", "moved_object"]
#
# # Get list of objects with details:
# >> cont.objects_detail
# => {"fosdem2012.pdf"=>{:bytes=>"493009", :content_type=>"application/json", :hash=>"494e444f92a8082dabac80a74cdf2c3b", :last_modified=>"2012-04-26T09:22:51.611230"}, "moved_object"=>{:bytes=>"38", :content_type=>"application/json", :hash=>"a7942f97fe6bd34920a4f61fe5e604a5", :last_modified=>"2012-04-26T09:35:33.839920"}}
#
# # Check if container is empty:
# >> cont.empty?
# => false
#
# # Check if object exists:
# >> cont.object_exists?("foo")
# => false
#
# # Create new object
# >> new_obj = cont.create_object("foo", {:metadata=>{"herpy"=>"derp"}, :content_type=>"text/plain"}, "this is the data")  [can also supply File.open(/path/to/file) and the data]
# => #<OpenStack::Swift::StorageObject:0xb72fdac0  ... etc
#
# # Delete object
# >> cont.delete_object("foo")
# => true
#
# # Get handle to an OpenStack::Swift::StorageObject Object
# >> obj = cont.object("foo")
# => #<OpenStack::Swift::StorageObject:0xb72fdac0  ... etc
#
# # Get object metadata
# >> obj.object_metadata
# =>
#
# # Get user defined metadata pairs
# >> obj.metadata
# =>
#
# # Get data (non streaming - returned as a String)
# >> obj.data
# => "This is the text stored in the file"
#
# # Get data (streaming - requires a block)
# >> data = ""; object.data_stream do |chunk| data += chunk end
# => #<Net::HTTPOK 200 OK readbody=true>
# >> data
# => "This is the text stored in the file"
#
# # Set user defined metadata
# >> obj.set_metadata({:foo=>"bar", "X-Object-Meta-herpa"=>"derp", "author"=>"me"})
# => true
#
# # (Over)Write object data
# >> object.write("This is new data")
# => true
# >> object.data
# => "This is new data"
#
# # Copy object:
# >>copied = obj.copy('copied_object', "destination_container", {:content_type=>"text/plain", :metadata=>{:herp=>"derp", "X-Object-Meta-foo"=>"bar} } )
# => #<OpenStack::Swift::StorageObject:0xb728974c  ..... etc
#
# # Move object: (copy and then delete original):
# >> moved = obj.move('moved_object', "destination_container", {:content_type=>"text/plain", :metadata=>{:herp=>"derp", "X-Object-Meta-foo"=>"bar"} } )
# =>  #<OpenStack::Swift::StorageObject:0xb7266bd4 ...
# >> moved.metadata
# => {"foo"=>"bar", "herp"=>"derp", "herpy"=>"derp"}
# >> obj.metadata
# => OpenStack::Exception::ItemNotFound: The resource could not be found
