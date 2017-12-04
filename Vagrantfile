# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://vagrantcloud.com/search.
  config.vm.box = "centos/7"

  config.vm.define :db1 do |m|
    m.vm.hostname = "db1"
    m.vm.provider "virtualbox" do |v|
      v.memory = 512
    end
    m.vm.network :private_network, ip: "192.168.33.11"
    m.vm.provision "shell", path: "setup.sh"
  end

  config.vm.define :db2 do |m|
    m.vm.hostname = "db2"
    m.vm.provider "virtualbox" do |v|
      v.memory = 512
    end
    m.vm.network :private_network, ip: "192.168.33.12"
    m.vm.provision "shell", path: "setup.sh"
  end

  config.vm.define :db3 do |m|
    m.vm.hostname = "db3"
    m.vm.provider "virtualbox" do |v|
      v.memory = 512
    end
    m.vm.network :private_network, ip: "192.168.33.13"
    m.vm.provision "shell", path: "setup.sh"
  end

  config.vm.define :client do |m|
    m.vm.hostname = "client"
    m.vm.provider "virtualbox" do |v|
      v.memory = 512
    end
    m.vm.network :private_network, ip: "192.168.33.20"
    m.vm.provision "shell", path: "setup-client.sh"
  end
end
