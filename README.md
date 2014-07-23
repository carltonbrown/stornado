storhole
========
# What this is:
* A minimal swift client that doesn't require Python or Nokogiri
* Driven by a JSON config file

# Prerequisites:
gem install openstack

# Usage:
* ruby storhole.rb repo get production-releases accounts-22311d8f0ef6d359190ced9ee3ab130bc2236f7d.tgz -r repo_config.json -p ch3-opc
* ruby storhole.rb repo put production-releases accounts-22311d8f0ef6d359190ced9ee3ab130bc2236f7d.tgz -r repo_config.json -p ch3-opc
* ruby storhole.rb repo ls production-releases accounts-22311d8f0ef6d359190ced9ee3ab130bc2236f7d.tgz -r repo_config.json -p ch3-opc
* ruby storhole.rb repo ls_l production-releases accounts-22311d8f0ef6d359190ced9ee3ab130bc2236f7d.tgz -r repo_config.json -p ch3-opc

# Configuration
* Refer to  your configuration using the -r flag.   See sample_repo_config.json for an example.
* In the command line, the names of the repository and proxy are aliases specified you in the repo_config.json file
