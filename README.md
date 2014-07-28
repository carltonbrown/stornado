storalizer
========
# What this is:
* A minimal swift client that doesn't require Python or Nokogiri
* Driven by a JSON config file

# Prerequisites:
gem install openstack

# Arguments:
* repo - commands to be done against a container (list files, list a particular file, upload a file, download a file, delete a file)
* service - commands to be done against a service (list containers, create containers, delete containers)

# Usage:
* storalizer repo ls big_bucket -r repo_config.json -p ch3-opc
* storalizer repo put big_bucket accounts-22.tgz -r repo_config.json -p ch3-opc
* storalizer repo ls big_bucket accounts-22.tgz -r repo_config.json -p ch3-opc
* storalizer repo get big_bucket accounts-22.tgz -r repo_config.json -p ch3-opc
* storalizer repo delete big_bucket accounts-22.tgz -r repo_config.json -p ch3-opc
* storalizer service our-account ls big_bucket -r repo_config.json 
* storalizer service our-account create big_bucket -r repo_config.json 
* storalizer service our-account delete big_bucket -r repo_config.json 

# Configuration
* Specify the config file with the -r flag.   See sample_repo_config.json for an example.
* Specify the proxy to use with the -p flag (refers to a proxy alias specified by you in your config file).
* The repository and service names are also aliases that you specify in your config file
