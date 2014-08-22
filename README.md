stornado
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
* stornado services # list configured services
* stornado repos # list configured repos
* stornado service our-account ls big_bucket
* stornado service our-account create big_bucket
* stornado service our-account delete big_bucket 
* stornado repo ls big_bucket -p ch3-opc  -r ~/config.json # Example with proxy and config file override
* stornado repo put big_bucket accounts-22.tgz
* stornado repo ls big_bucket accounts-22.tgz
* stornado repo get big_bucket accounts-22.tgz
* stornado repo delete big_bucket accounts-22.tgz

# Configuration
* Config file defaults to ~/.stornado/repo-config.json.  Override the config file path with -r flag.   See sample_repo_config.json for an example.
* Specify the proxy to use with the -p flag (refers to a proxy alias specified by you in your config file).
* The repository and service names are also aliases that you specify in your config file

# Testing
* To run locally:  ruby -Ilib/ bin/stornado repo srm-rc ls -r prod_machine_repo_config.json

# Changes
* Now recognizes the HTTP_PROXY variable
